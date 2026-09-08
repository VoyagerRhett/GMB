#include "citizen_sdk_qr_camera.hpp"
#include <windows.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <thread>
#include <utility>
#include "citizen_sdk_host_record.hpp"
namespace citizen_sdk::windows {
using Microsoft::WRL::ComPtr;
namespace {
struct Samples final {
  std::mutex lock;
  std::condition_variable changed;
  ComPtr<IMFSample> sample;
  HRESULT error{S_OK};
  bool ended{};
  bool sample_ready{};
  unsigned callbacks{};
};
class ReaderCallback final : public IMFSourceReaderCallback {
 public:
  explicit ReaderCallback(std::shared_ptr<Samples> state) : state_(std::move(state)) {}
  STDMETHODIMP QueryInterface(REFIID id, void **out) override {
    if (out == nullptr) return E_POINTER;
    *out = nullptr;
    if (id == __uuidof(IUnknown) || id == __uuidof(IMFSourceReaderCallback))
      *out = static_cast<IMFSourceReaderCallback *>(this);
    else return E_NOINTERFACE;
    AddRef(); return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
  STDMETHODIMP_(ULONG) Release() override {
    const ULONG remaining = --references_; if (remaining == 0) delete this; return remaining;
  }
  STDMETHODIMP OnReadSample(HRESULT status, DWORD, DWORD flags, LONGLONG, IMFSample *sample) override {
    std::lock_guard<std::mutex> guard(state_->lock);
    ++state_->callbacks;
    if (FAILED(status)) state_->error = status;
    if ((flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) state_->ended = true;
    if ((flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) != 0)
      state_->error = MF_E_INVALIDMEDIATYPE;
    state_->sample_ready = true;
    state_->sample = sample;
    --state_->callbacks; state_->changed.notify_all(); return S_OK;
  }
  STDMETHODIMP OnFlush(DWORD) override { state_->changed.notify_all(); return S_OK; }
  STDMETHODIMP OnEvent(DWORD, IMFMediaEvent *event) override {
    HRESULT status = S_OK;
    if (event != nullptr && SUCCEEDED(event->GetStatus(&status)) && FAILED(status)) {
      std::lock_guard<std::mutex> guard(state_->lock);
      state_->error = status; state_->changed.notify_all();
    }
    return S_OK;
  }
 private:
  std::atomic<ULONG> references_{1};
  std::shared_ptr<Samples> state_;
};
void check(HRESULT status, const char *message) {
  require(SUCCEEDED(status), status == E_ACCESSDENIED ? CITIZENSDK_ERROR_PERMISSION_DENIED
                                                   : CITIZENSDK_ERROR_UNAVAILABLE, message);
}
}
struct QrCamera::Impl final {
  Frame frame;
  Failure failure;
  std::atomic<bool> stopping{false};
  std::shared_ptr<Samples> samples{std::make_shared<Samples>()};
  std::thread worker;
  Impl(Frame value, Failure error) : frame(std::move(value)), failure(std::move(error)) {}
  void run() noexcept {
    bool com_started = false;
    bool media_started = false;
    ComPtr<IMFMediaSource> source;
    ComPtr<IMFSourceReader> reader;
    ComPtr<ReaderCallback> callback;
    IMFActivate **devices = nullptr;
    UINT32 count = 0;
    try {
      check(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "COM 摄像头线程初始化失败");
      com_started = true;
      check(MFStartup(MF_VERSION, MFSTARTUP_FULL), "Media Foundation 不可用");
      media_started = true;
      ComPtr<IMFAttributes> attributes;
      check(MFCreateAttributes(&attributes, 3), "摄像头枚举不可用");
      check(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID), "摄像头类型设置失败");
      check(MFEnumDeviceSources(attributes.Get(), &devices, &count), "无法枚举摄像头");
      require(count != 0 && devices != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "未发现可用摄像头");
      check(devices[0]->ActivateObject(IID_PPV_ARGS(&source)), "摄像头不可用，请检查 Windows 相机权限");
      callback.Attach(new ReaderCallback(samples));
      attributes.Reset();
      check(MFCreateAttributes(&attributes, 3), "摄像头读取器初始化失败");
      check(attributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, callback.Get()), "异步采集配置失败");
      check(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE), "像素转换配置失败");
      check(MFCreateSourceReaderFromMediaSource(source.Get(), attributes.Get(), &reader), "摄像头启动被拒绝");
      ComPtr<IMFMediaType> requested;
      check(MFCreateMediaType(&requested), "像素类型创建失败");
      check(requested->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video), "视频格式无效");
      check(requested->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32), "RGB32 格式不可用");
      check(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, requested.Get()),
            "摄像头不支持安全有界像素转换");
      ComPtr<IMFMediaType> actual;
      check(reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &actual), "无法读取实际像素格式");
      UINT32 width = 0, height = 0;
      check(MFGetAttributeSize(actual.Get(), MF_MT_FRAME_SIZE, &width, &height), "摄像头尺寸无效");
      require(width > 0 && height > 0 && width <= 4096 && height <= 4096,
              CITIZENSDK_ERROR_INVALID_ARGUMENT, "摄像头尺寸超过上限");
      UINT32 encoded_stride = 0;
      LONG stride = 0;
      if (SUCCEEDED(actual->GetUINT32(MF_MT_DEFAULT_STRIDE, &encoded_stride))) {
        static_assert(sizeof(stride) == sizeof(encoded_stride));
        std::memcpy(&stride, &encoded_stride, sizeof(stride));
      } else check(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride),
                   "摄像头行跨度不可用");
      const auto pitch = static_cast<std::size_t>(stride < 0 ? -static_cast<int64_t>(stride) : stride);
      require(pitch >= static_cast<std::size_t>(width) * 4 && pitch <= 16 * 1024 * 1024 &&
                  pitch * height <= 64 * 1024 * 1024,
              CITIZENSDK_ERROR_INVALID_ARGUMENT, "摄像头帧跨度超过上限");
      while (!stopping.load()) {
        {
          std::lock_guard<std::mutex> guard(samples->lock); samples->sample.Reset(); samples->sample_ready = false;
          if (FAILED(samples->error) || samples->ended)
            throw HostError(CITIZENSDK_ERROR_UNAVAILABLE, "摄像头断开或读取失败");
        }
        check(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, nullptr, nullptr, nullptr),
              "摄像头采集请求失败");
        ComPtr<IMFSample> sample;
        {
          std::unique_lock<std::mutex> guard(samples->lock);
          samples->changed.wait(guard, [&] {
            return stopping.load() || samples->sample_ready || FAILED(samples->error) || samples->ended;
          });
          if (stopping.load()) break;
          if (FAILED(samples->error) || samples->ended)
            throw HostError(CITIZENSDK_ERROR_UNAVAILABLE, "摄像头断开或采集失败");
          sample = std::move(samples->sample);
        }
        if (!sample) continue;
        ComPtr<IMFMediaBuffer> buffer;
        check(sample->ConvertToContiguousBuffer(&buffer), "摄像头帧缓冲读取失败");
        BYTE *data = nullptr; DWORD length = 0;
        check(buffer->Lock(&data, nullptr, &length), "摄像头帧无法映射");
        QrFrame output;
        try {
          require(data != nullptr && length >= pitch * height, CITIZENSDK_ERROR_INTEGRITY,
                  "摄像头像素缓冲被截断");
          output.width = width; output.height = height;
          output.luminance.resize(static_cast<std::size_t>(width) * height);
          for (uint32_t y = 0; y < height; ++y) {
            const auto *row = data + static_cast<std::size_t>(stride < 0 ? height - 1 - y : y) * pitch;
            for (uint32_t x = 0; x < width; ++x) {
              const auto *pixel = row + static_cast<std::size_t>(x) * 4;
              output.luminance[static_cast<std::size_t>(y) * width + x] =
                  static_cast<uint8_t>((77U * pixel[2] + 150U * pixel[1] + 29U * pixel[0]) >> 8);
            }
          }
        } catch (...) { buffer->Unlock(); throw; }
        check(buffer->Unlock(), "摄像头帧解除映射失败");
        if (!stopping.load()) frame(std::move(output));
      }
    } catch (const HostError &error) {
      if (!stopping.load()) { try { failure(error.code(), error.what()); } catch (...) {} }
    } catch (...) {
      if (!stopping.load()) { try { failure(CITIZENSDK_ERROR_INTERNAL, "摄像头采集失败"); } catch (...) {} }
    }
    // 停止底层设备在前，释放回调引用在后；上层 stop() 只在此线程退出后完成。
    if (reader) reader->Flush(MF_SOURCE_READER_ALL_STREAMS);
    if (source) source->Shutdown();
    reader.Reset(); source.Reset(); callback.Reset();
    { std::lock_guard<std::mutex> guard(samples->lock); samples->sample.Reset(); }
    if (devices != nullptr) {
      for (UINT32 index = 0; index < count; ++index) devices[index]->Release();
      CoTaskMemFree(devices);
    }
    if (media_started) MFShutdown();
    if (com_started) CoUninitialize();
  }
};
QrCamera::QrCamera(Frame frame, Failure failure)
    : impl_(std::make_unique<Impl>(std::move(frame), std::move(failure))) {}
QrCamera::~QrCamera() { stop(); }
void QrCamera::start() {
  require(!impl_->worker.joinable(), CITIZENSDK_ERROR_INVALID_STATE, "相机已经启动");
  impl_->worker = std::thread([this] { impl_->run(); });
}
void QrCamera::stop() noexcept {
  impl_->stopping.store(true); impl_->samples->changed.notify_all();
  if (impl_->worker.joinable()) {
    if (impl_->worker.get_id() == std::this_thread::get_id()) std::terminate();
    impl_->worker.join();
  }
}
}  // namespace citizen_sdk::windows
