#include "citizen_sdk_qr_camera.hpp"
#include <atomic>
#include <cstring>
#include <thread>
#include <utility>
#include "citizen_sdk_host_record.hpp"
#if CITIZENSDK_ENABLE_WALLET_UI
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/video.h>
#endif
namespace citizen_sdk::linux {
struct QrCamera::Impl final {
  Frame frame;
  Failure failure;
  std::atomic<bool> stopping{false};
  std::thread worker;
  Impl(Frame value, Failure error) : frame(std::move(value)), failure(std::move(error)) {}
  void run() noexcept {
#if CITIZENSDK_ENABLE_WALLET_UI
    GstDeviceMonitor *monitor = nullptr;
    GstElement *pipeline = nullptr;
    GstBus *bus = nullptr;
    GList *devices = nullptr;
    try {
      GError *error = nullptr;
      if (!gst_init_check(nullptr, nullptr, &error)) {
        if (error != nullptr) g_error_free(error);
        throw HostError(CITIZENSDK_ERROR_UNAVAILABLE, "GStreamer 摄像头运行环境不可用");
      }
      monitor = gst_device_monitor_new();
      require(monitor != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "摄像头枚举不可用");
      GstCaps *filter = gst_caps_from_string("video/x-raw");
      const guint filter_id = gst_device_monitor_add_filter(monitor, "Video/Source", filter);
      gst_caps_unref(filter);
      require(filter_id != 0 && gst_device_monitor_start(monitor),
              CITIZENSDK_ERROR_UNAVAILABLE, "无法枚举摄像头，请检查设备与权限");
      devices = gst_device_monitor_get_devices(monitor);
      require(devices != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "未发现可用摄像头");
      pipeline = gst_pipeline_new(nullptr);
      require(pipeline != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法创建摄像头管线");
      GstElement *source = gst_device_create_element(GST_DEVICE(devices->data), nullptr);
      require(source != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法打开摄像头，请检查设备权限");
      gst_bin_add(GST_BIN(pipeline), source);
      auto add = [&](const char *factory) {
        GstElement *element = gst_element_factory_make(factory, nullptr);
        require(element != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "缺少正式 GStreamer 采集组件");
        gst_bin_add(GST_BIN(pipeline), element);
        return element;
      };
      GstElement *convert = add("videoconvert");
      GstElement *scale = add("videoscale");
      GstElement *caps_filter = add("capsfilter");
      GstElement *sink = add("appsink");
      GstCaps *caps = gst_caps_from_string("video/x-raw,format=GRAY8,width=640,height=480");
      g_object_set(caps_filter, "caps", caps, nullptr);
      gst_caps_unref(caps);
      g_object_set(sink, "max-buffers", 1U, "drop", TRUE, "sync", FALSE, nullptr);
      require(gst_element_link_many(source, convert, scale, caps_filter, sink, nullptr),
              CITIZENSDK_ERROR_UNAVAILABLE, "摄像头像素格式无法转换");
      bus = gst_element_get_bus(pipeline);
      require(bus != nullptr &&
                  gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE,
              CITIZENSDK_ERROR_UNAVAILABLE, "摄像头启动被拒绝");
      while (!stopping.load()) {
        GstMessage *message = gst_bus_pop_filtered(bus,
            static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
        if (message != nullptr) {
          gst_message_unref(message);
          throw HostError(CITIZENSDK_ERROR_UNAVAILABLE, "摄像头断开或采集失败");
        }
        GstSample *sample = gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 50 * GST_MSECOND);
        if (sample == nullptr) continue;
        GstVideoInfo info{};
        GstVideoFrame video{};
        GstCaps *sample_caps = gst_sample_get_caps(sample);
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        const bool valid = sample_caps != nullptr && buffer != nullptr &&
            gst_video_info_from_caps(&info, sample_caps) &&
            GST_VIDEO_INFO_FORMAT(&info) == GST_VIDEO_FORMAT_GRAY8 &&
            GST_VIDEO_INFO_WIDTH(&info) > 0 && GST_VIDEO_INFO_WIDTH(&info) <= 4096 &&
            GST_VIDEO_INFO_HEIGHT(&info) > 0 && GST_VIDEO_INFO_HEIGHT(&info) <= 4096 &&
            gst_video_frame_map(&video, &info, buffer, GST_MAP_READ);
        if (!valid) {
          gst_sample_unref(sample);
          throw HostError(CITIZENSDK_ERROR_INTEGRITY, "摄像头返回无效亮度帧");
        }
        QrFrame output;
        const gint stride = GST_VIDEO_FRAME_PLANE_STRIDE(&video, 0);
        const auto width = GST_VIDEO_INFO_WIDTH(&info);
        const auto height = GST_VIDEO_INFO_HEIGHT(&info);
        if (stride < width) {
          gst_video_frame_unmap(&video); gst_sample_unref(sample);
          throw HostError(CITIZENSDK_ERROR_INTEGRITY, "摄像头行跨度无效");
        }
        try {
          output.width = static_cast<uint32_t>(width);
          output.height = static_cast<uint32_t>(height);
          output.luminance.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height));
          const auto *pixels = static_cast<const uint8_t *>(GST_VIDEO_FRAME_PLANE_DATA(&video, 0));
          for (gint row = 0; row < height; ++row)
            std::memcpy(output.luminance.data() + static_cast<std::size_t>(row) * output.width,
                        pixels + static_cast<std::size_t>(row) * static_cast<std::size_t>(stride),
                        output.width);
        } catch (...) {
          gst_video_frame_unmap(&video); gst_sample_unref(sample); throw;
        }
        gst_video_frame_unmap(&video); gst_sample_unref(sample);
        if (!stopping.load()) frame(std::move(output));
      }
    } catch (const HostError &error) {
      if (!stopping.load()) { try { failure(error.code(), error.what()); } catch (...) {} }
    } catch (...) {
      if (!stopping.load()) { try { failure(CITIZENSDK_ERROR_INTERNAL, "摄像头采集失败"); } catch (...) {} }
    }
    if (pipeline != nullptr) gst_element_set_state(pipeline, GST_STATE_NULL);
    if (bus != nullptr) gst_object_unref(bus);
    if (pipeline != nullptr) gst_object_unref(pipeline);
    if (devices != nullptr) g_list_free_full(devices, g_object_unref);
    if (monitor != nullptr) { gst_device_monitor_stop(monitor); gst_object_unref(monitor); }
#else
    try { failure(CITIZENSDK_ERROR_UNSUPPORTED, "此构建未启用 GTK/GStreamer 原生扫码界面"); } catch (...) {}
#endif
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
  impl_->stopping.store(true);
  if (impl_->worker.joinable()) {
    if (impl_->worker.get_id() == std::this_thread::get_id()) std::terminate();
    impl_->worker.join();
  }
}
}  // namespace citizen_sdk::linux
