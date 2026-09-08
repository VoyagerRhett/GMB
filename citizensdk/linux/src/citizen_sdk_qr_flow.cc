#include "citizen_sdk_qr_flow.hpp"
#include "citizen_sdk_qr_camera.hpp"
#include "citizen_sdk_wallet_flow.hpp"
#include "citizensdk_qr_image.h"
#include <atomic>
#include <cstring>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>
#if CITIZENSDK_ENABLE_WALLET_UI
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <unistd.h>
#endif

namespace citizen_sdk::linux {
namespace {
constexpr uint64_t kDocumentLimit = 65536;
std::mutex qr_flows_lock;
class QrFlow;
std::unordered_map<citizensdk_wallet_flow_handle_t, std::shared_ptr<QrFlow>> qr_flows;

citizensdk_bytes_view_t qr_view(const std::string &value) {
  return {reinterpret_cast<const uint8_t *>(value.data()), static_cast<uint64_t>(value.size())};
}
template <typename Copy> std::string copy_document(Copy copy) {
  uint64_t length = 0;
  auto code = copy(nullptr, 0, &length);
  require(code == CITIZENSDK_OK, code, "二维码核心处理失败");
  require(length > 0 && length <= kDocumentLimit, CITIZENSDK_ERROR_INTEGRITY, "二维码核心结果超出上限");
  std::string value(static_cast<std::size_t>(length), '\0');
  uint64_t copied = length;
  code = copy(reinterpret_cast<uint8_t *>(value.data()), length, &copied);
  require(code == CITIZENSDK_OK, code, "二维码核心结果读取失败");
  require(copied == length, CITIZENSDK_ERROR_INTEGRITY, "二维码核心结果长度改变");
  return value;
}

// 原生只排版 Core 的已审阅 JSON，不重解 SCALE、不重建签名数据。
[[maybe_unused]] std::string display_document(const std::string &value) {
  std::string result;
  result.reserve(value.size() + 128);
  bool quoted = false, escaped = false;
  for (const char ch : value) {
    result.push_back(ch);
    if (escaped) { escaped = false; continue; }
    if (quoted && ch == '\\') { escaped = true; continue; }
    if (ch == '"') quoted = !quoted;
    if (!quoted && (ch == ',' || ch == '{' || ch == '}')) result.push_back('\n');
  }
  return result;
}

class QrFlow final : public std::enable_shared_from_this<QrFlow> {
 public:
  QrFlow(citizensdk_wallet_flow_handle_t handle, std::shared_ptr<HostBridge> host,
         uint64_t token, std::string request, void *context,
         citizensdk_qr_completion_v1_t completion)
      : handle_(handle), host_(std::move(host)), token_(token),
        sign_request_(std::move(request)), context_(context), completion_(completion) {}
  ~QrFlow() { destroy_ui(); }
  void start();
  void cancel() noexcept { cancellation_.cancel(); }
  bool belongs_to(const HostBridge *host) const noexcept { return host_.get() == host; }
  void confirm() noexcept;
  bool tick() noexcept;
 private:
  void create_ui();
  void destroy_ui() noexcept;
  void hide_ui() noexcept;
  void set_review(const std::string &value);
  void preview(const QrFrame &frame);
  void set_busy();
  bool session_safe() noexcept;
  void submit(bool signing);
  void receive_frame(QrFrame frame) noexcept;
  void receive_result(citizensdk_result_handle_t result) noexcept;
  void fail(citizensdk_error_code_t error) noexcept;
  void begin_cleanup() noexcept;
  void complete() noexcept;
  citizensdk_wallet_flow_handle_t handle_;
  std::shared_ptr<HostBridge> host_;
  uint64_t token_;
  std::string sign_request_;
  void *context_;
  citizensdk_qr_completion_v1_t completion_;
  std::unique_ptr<QrCamera> camera_;
  std::mutex lock_;
  std::optional<QrFrame> frame_;
  std::string scanned_;
  citizensdk_error_code_t failure_{CITIZENSDK_OK};
  citizensdk_result_handle_t pending_result_{};
  citizensdk_result_handle_t review_{};
  citizensdk_request_id_t request_{};
  citizensdk_request_id_t cancellation_sent_{};
  QrFlowCancellation cancellation_;
  std::atomic<bool> camera_stopped_{false};
  bool cleanup_started_{};
  bool started_{};
  bool result_ready_{};
  bool core_active_{};
  bool confirmed_{};
  bool finished_{};
  citizensdk_error_code_t outcome_{CITIZENSDK_OK};
  std::string document_;
#if CITIZENSDK_ENABLE_WALLET_UI
  bool activated_{};
  GtkWidget *window_{}, *image_{}, *text_{}, *button_{}, *parent_{};
  GMainContext *ui_context_{};
  GSource *timer_{};
  GDBusProxy *session_{}, *manager_{};
  bool hiding_{};
#endif
};

void QrFlow::start() {
  create_ui();
  // UI 与监督已建立后才接纳底层任务；此后所有错误走同一个真实终态。
  try {
    if (sign_request_.empty()) {
      const std::weak_ptr<QrFlow> weak = shared_from_this();
      camera_ = std::make_unique<QrCamera>(
          [weak](QrFrame frame) { if (auto self = weak.lock()) self->receive_frame(std::move(frame)); },
          [weak](citizensdk_error_code_t error, std::string) {
            if (auto self = weak.lock()) self->fail(error);
          });
      camera_->start();
    } else {
      camera_stopped_.store(true);
      submit(false);
    }
  } catch (...) { fail(map_exception()); }
  // 创建/显示窗口可能泵送嵌套消息；接纳返回前禁止 timer 暴露最终 completion。
  started_ = true;
}

void QrFlow::submit(bool signing) {
  require(!core_active_ && !cancellation_.closing(), CITIZENSDK_ERROR_INVALID_STATE, "二维码任务状态无效");
  core_active_ = true;
  request_ = 0;
  const auto self = shared_from_this();
  const auto code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return signing ? citizensdk_sign_qr_request(host_->sdk(), review_, out)
                       : citizensdk_review_qr_sign_request(host_->sdk(), qr_view(sign_request_), out);
      }, [self](citizensdk_result_handle_t result) noexcept { self->receive_result(result); }, &request_);
  // 只有 Core 接纳之后才释放不可变审阅凭证；拒绝也必须走真实清理。
  if (signing && review_ != 0) {
    const auto release = citizensdk_result_release(review_);
    if (release == CITIZENSDK_OK) review_ = 0;
    else fail(release);
  }
  if (code != CITIZENSDK_OK) { core_active_ = false; request_ = 0; fail(code); }
}

void QrFlow::receive_result(citizensdk_result_handle_t result) noexcept {
  std::lock_guard<std::mutex> guard(lock_);
  // 一次只允许一个 Core 请求；不吞掉异常重复句柄。
  if (result_ready_) std::terminate();
  result_ready_ = true;
  pending_result_ = result;
}

void QrFlow::receive_frame(QrFrame frame) noexcept {
  if (cancellation_.closing() || cancellation_.cancelled()) return;
  try {
    // 相机输出唯一灰度缓冲，识别严格交给同一 ZXing 窄 ABI。
    size_t required = 0;
    const auto first = citizensdk_qr_image_decode_luminance(
        frame.luminance.data(), frame.luminance.size(), frame.width, frame.height,
        frame.width, nullptr, 0, &required);
    std::string parsed;
    if (first == CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL) {
      require(required > 0 && required <= 2331, CITIZENSDK_ERROR_INTEGRITY, "扫码文本超出上限");
      std::string text(required, '\0');
      size_t copied = required;
      const auto decoded = citizensdk_qr_image_decode_luminance(
          frame.luminance.data(), frame.luminance.size(), frame.width, frame.height,
          frame.width, reinterpret_cast<uint8_t *>(text.data()), text.size(), &copied);
      require(decoded == CITIZENSDK_QR_IMAGE_OK && copied == required,
              CITIZENSDK_ERROR_INTEGRITY, "扫码结果不稳定");
      parsed = copy_document([&](uint8_t *out, uint64_t capacity, uint64_t *size) {
        return citizensdk_qr_parse(host_->sdk(), qr_view(text), out, capacity, size);
      });
    } else if (first != CITIZENSDK_QR_IMAGE_NO_CODE) {
      // 多码、非 UTF-8、错误像素都不得任意选择一个或交给另一识别器。
      citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
      switch (first) {
        case CITIZENSDK_QR_IMAGE_MULTIPLE_CODES: code = CITIZENSDK_ERROR_CONFLICT; break;
        case CITIZENSDK_QR_IMAGE_INVALID_ARGUMENT:
        case CITIZENSDK_QR_IMAGE_CAPACITY_EXCEEDED: code = CITIZENSDK_ERROR_INVALID_ARGUMENT; break;
        case CITIZENSDK_QR_IMAGE_INVALID_UTF8: code = CITIZENSDK_ERROR_DECODE; break;
        default: break;
      }
      fail(code);
      return;
    }
    std::lock_guard<std::mutex> guard(lock_);
    if (cancellation_.closing() || cancellation_.cancelled()) return;
    frame_ = std::move(frame);  // 仅保留最新一帧，防止主线程阻塞引起无限排队。
    if (!parsed.empty() && scanned_.empty()) scanned_ = std::move(parsed);
  } catch (...) { fail(map_exception()); }
}

void QrFlow::fail(citizensdk_error_code_t error) noexcept {
  std::lock_guard<std::mutex> guard(lock_);
  if (failure_ == CITIZENSDK_OK) failure_ = error == CITIZENSDK_OK ? CITIZENSDK_ERROR_INTERNAL : error;
}

void QrFlow::confirm() noexcept {
  if (confirmed_ || cancellation_.closing() || cancellation_.cancelled() || review_ == 0) return;
  try {
    require(session_safe(), CITIZENSDK_ERROR_CANCELLED, "桌面会话已离开");
    confirmed_ = true;
    set_busy();
    submit(true);
  } catch (...) { fail(map_exception()); }
}

void QrFlow::begin_cleanup() noexcept {
  if (!cancellation_.begin_cleanup()) hide_ui();
  if (review_ != 0) {
    const auto code = citizensdk_result_release(review_);
    if (code == CITIZENSDK_OK) review_ = 0;
    else if (outcome_ == CITIZENSDK_OK) outcome_ = code;
  }
  if (core_active_ && request_ != 0 && cancellation_sent_ != request_) {
    // 取消不等于终态；认证中的签名必须等普通 Core completion 真正排空。
    const auto code = citizensdk_cancel_request(host_->sdk(), request_);
    if (code == CITIZENSDK_OK || code == CITIZENSDK_ERROR_INVALID_ARGUMENT ||
        code == CITIZENSDK_ERROR_INVALID_STATE || code == CITIZENSDK_ERROR_NOT_FOUND)
      cancellation_sent_ = request_;
  }
  if (!camera_) { camera_stopped_.store(true); return; }
  if (cleanup_started_) return;
  try {
    auto self = shared_from_this();
    std::thread worker([self] {
      self->camera_->stop();
      self->camera_stopped_.store(true);
    });
    worker.detach();
    cleanup_started_ = true;
  } catch (...) {
    // 保持窗口隐藏与租约，下一 UI tick 重试；绝不在 UI 线程 join 摄像头。
    if (outcome_ == CITIZENSDK_OK) outcome_ = CITIZENSDK_ERROR_UNAVAILABLE;
  }
}

bool QrFlow::tick() noexcept {
  if (finished_) return false;
  if (!started_) return true;
  try {
    if (!cancellation_.closing() && !session_safe()) cancellation_.cancel();
    citizensdk_result_handle_t result = 0;
    bool result_ready = false;
    std::optional<QrFrame> frame;
    std::string scanned;
    {
      std::lock_guard<std::mutex> guard(lock_);
      result = std::exchange(pending_result_, 0);
      result_ready = std::exchange(result_ready_, false);
      frame = std::move(frame_); frame_.reset();
      scanned = std::move(scanned_); scanned_.clear();
      if (failure_ != CITIZENSDK_OK && outcome_ == CITIZENSDK_OK) outcome_ = failure_;
    }
    if (cancellation_.cancelled()) outcome_ = CITIZENSDK_ERROR_CANCELLED;
    if (result_ready) {
      core_active_ = false; request_ = 0;
      citizensdk_result_info_t info{};
      info.struct_size = sizeof(info); info.abi_version = 1;
      auto code = result == 0 ? CITIZENSDK_ERROR_INTEGRITY : citizensdk_result_get_info(result, &info);
      if (code == CITIZENSDK_OK) code = info.error_code;
      if (code == CITIZENSDK_OK &&
          info.kind != (confirmed_ ? CITIZENSDK_RESULT_QR_SIGNED : CITIZENSDK_RESULT_QR_REVIEW))
        code = CITIZENSDK_ERROR_INTEGRITY;
      if (code == CITIZENSDK_OK && outcome_ == CITIZENSDK_OK && !cancellation_.closing()) {
        try {
          auto value = copy_document([&](uint8_t *out, uint64_t capacity, uint64_t *size) {
            return citizensdk_result_copy_qr(result, out, capacity, size);
          });
          if (confirmed_) document_ = std::move(value);
          else {
            review_ = result; result = 0;
            set_review(value);
          }
        } catch (...) { code = map_exception(); }
      }
      if (result != 0) {
        const auto released = citizensdk_result_release(result);
        if (released != CITIZENSDK_OK) std::terminate();  // 不丢失尚未释放的 Core 句柄。
      }
      if (code != CITIZENSDK_OK && outcome_ == CITIZENSDK_OK) outcome_ = code;
    }
    if (!cancellation_.closing() && outcome_ == CITIZENSDK_OK) {
      if (frame) preview(*frame);
      if (!scanned.empty()) document_ = std::move(scanned);
    }
    if (outcome_ != CITIZENSDK_OK || !document_.empty() || cancellation_.closing()) begin_cleanup();
    if (cancellation_.closing() && !core_active_ && review_ == 0 && camera_stopped_.load()) {
      complete();
      return false;
    }
  } catch (...) {
    if (outcome_ == CITIZENSDK_OK) outcome_ = map_exception();
    begin_cleanup();
  }
  return true;
}

void QrFlow::complete() noexcept {
  if (finished_) return;
  finished_ = true;
  const auto keep_alive = shared_from_this();
  destroy_ui();
  camera_.reset();
  { std::lock_guard<std::mutex> guard(lock_); frame_.reset(); scanned_.clear(); }
  host_->finish_wallet_flow(token_);
  { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.erase(handle_); }
  if (cancellation_.cancelled()) outcome_ = CITIZENSDK_ERROR_CANCELLED;
  if (outcome_ != CITIZENSDK_OK) document_.clear();
  try { completion_(context_, outcome_, qr_view(document_)); } catch (...) {}
}


void QrFlow::create_ui() {
#if CITIZENSDK_ENABLE_WALLET_UI
  require(gtk_init_check(nullptr, nullptr) != FALSE, CITIZENSDK_ERROR_UNAVAILABLE, "GTK 桌面不可用");
  ui_context_ = g_main_context_ref_thread_default();
  auto parent = host_->acquire_parent_window();
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  require(window_ != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法创建二维码窗口");
  gtk_window_set_title(GTK_WINDOW(window_), sign_request_.empty() ? "CitizenSDK 扫码" : "CitizenSDK 安全签名审阅");
  gtk_window_set_default_size(GTK_WINDOW(window_), 760, 640);
  if (parent.get() != nullptr) {
    gtk_window_set_transient_for(GTK_WINDOW(window_), GTK_WINDOW(parent.get()));
    gtk_window_set_destroy_with_parent(GTK_WINDOW(window_), FALSE);
    parent_ = GTK_WIDGET(parent.get());
    g_object_add_weak_pointer(G_OBJECT(parent_), reinterpret_cast<gpointer *>(&parent_));
    g_signal_connect(parent_, "destroy", G_CALLBACK((+[](GtkWidget *, gpointer data) {
      static_cast<QrFlow *>(data)->cancel();
    })), this);
  }
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_container_set_border_width(GTK_CONTAINER(box), 16);
  gtk_container_add(GTK_CONTAINER(window_), box);
  GtkWidget *title = gtk_label_new(sign_request_.empty()
      ? "将一个二维码放入画面。解析规则和有效期由 CitizenSDK Core 校验。"
      : "逐项核对 Core 验证的网络、签名账户、操作与全部参数。确认后才进行设备认证。");
  gtk_label_set_line_wrap(GTK_LABEL(title), TRUE);
  gtk_box_pack_start(GTK_BOX(box), title, FALSE, FALSE, 0);
  if (sign_request_.empty()) {
    image_ = gtk_image_new();
    gtk_box_pack_start(GTK_BOX(box), image_, TRUE, TRUE, 0);
  } else {
    GtkWidget *scroll = gtk_scrolled_window_new(nullptr, nullptr);
    text_ = gtk_text_view_new();
    gtk_text_view_set_editable(GTK_TEXT_VIEW(text_), FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(text_), FALSE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(text_), GTK_WRAP_WORD_CHAR);
    gtk_container_add(GTK_CONTAINER(scroll), text_);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);
    gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_)), "正在读取经验证的最终区块 metadata…", -1);
    button_ = gtk_button_new_with_label("我已完整核对，确认签名");
    gtk_widget_set_sensitive(button_, FALSE);
    g_signal_connect(button_, "clicked", G_CALLBACK((+[](GtkButton *, gpointer data) {
      static_cast<QrFlow *>(data)->confirm();
    })), this);
    gtk_box_pack_start(GTK_BOX(box), button_, FALSE, FALSE, 0);
  }
  GtkWidget *cancel = gtk_button_new_with_label("取消");
  g_signal_connect(cancel, "clicked", G_CALLBACK((+[](GtkButton *, gpointer data) {
    static_cast<QrFlow *>(data)->cancel();
  })), this);
  gtk_box_pack_start(GTK_BOX(box), cancel, FALSE, FALSE, 0);
  g_signal_connect(window_, "delete-event", G_CALLBACK((+[](GtkWidget *, GdkEvent *, gpointer data) -> gboolean {
    static_cast<QrFlow *>(data)->cancel(); return TRUE;
  })), this);
  g_signal_connect(window_, "focus-in-event", G_CALLBACK((+[](GtkWidget *, GdkEventFocus *, gpointer data) -> gboolean {
    static_cast<QrFlow *>(data)->activated_ = true; return FALSE;
  })), this);
  g_signal_connect(window_, "focus-out-event", G_CALLBACK((+[](GtkWidget *, GdkEventFocus *, gpointer data) -> gboolean {
    auto *self = static_cast<QrFlow *>(data);
    if (self->activated_ && !self->confirmed_ && !self->cancellation_.closing()) self->cancel();
    return FALSE;
  })), this);
  g_signal_connect(window_, "window-state-event", G_CALLBACK((+[](GtkWidget *, GdkEventWindowState *event, gpointer data) -> gboolean {
    if ((event->new_window_state & (GDK_WINDOW_STATE_ICONIFIED | GDK_WINDOW_STATE_WITHDRAWN)) != 0) {
      auto *self = static_cast<QrFlow *>(data);
      if (!self->hiding_) self->cancel();
    }
    return FALSE;
  })), this);
  g_signal_connect(window_, "unmap", G_CALLBACK((+[](GtkWidget *, gpointer data) {
    auto *self = static_cast<QrFlow *>(data); if (!self->hiding_) self->cancel();
  })), this);
  // 真实 logind 会话及初值必须可用；不把“未收到锁屏信号”当作安全。
  manager_ = g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SYSTEM,
      G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START, nullptr, "org.freedesktop.login1",
      "/org/freedesktop/login1", "org.freedesktop.login1.Manager", nullptr, nullptr);
  require(manager_ != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法建立桌面会话监督");
  GVariant *reply = g_dbus_proxy_call_sync(manager_, "GetSessionByPID",
      g_variant_new("(u)", static_cast<guint32>(getpid())),
      G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, nullptr, nullptr);
  require(reply != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法识别当前桌面会话");
  const gchar *path = nullptr;
  if (g_variant_is_of_type(reply, G_VARIANT_TYPE("(o)"))) g_variant_get(reply, "(&o)", &path);
  session_ = path == nullptr ? nullptr : g_dbus_proxy_new_for_bus_sync(G_BUS_TYPE_SYSTEM,
      G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START, nullptr, "org.freedesktop.login1", path,
      "org.freedesktop.login1.Session", nullptr, nullptr);
  g_variant_unref(reply);
  require(session_safe(), CITIZENSDK_ERROR_UNAVAILABLE, "桌面会话监督不可用或已锁屏");
  g_signal_connect(session_, "g-signal", G_CALLBACK((+[](GDBusProxy *, const gchar *,
      const gchar *signal, GVariant *, gpointer data) {
    if (std::strcmp(signal, "Lock") == 0) static_cast<QrFlow *>(data)->cancel();
  })), this);
  g_signal_connect(manager_, "g-signal", G_CALLBACK((+[](GDBusProxy *, const gchar *,
      const gchar *signal, GVariant *parameters, gpointer data) {
    if (std::strcmp(signal, "PrepareForSleep") != 0 && std::strcmp(signal, "PrepareForShutdown") != 0) return;
    gboolean active = TRUE;
    if (g_variant_is_of_type(parameters, G_VARIANT_TYPE("(b)"))) g_variant_get(parameters, "(b)", &active);
    if (active) static_cast<QrFlow *>(data)->cancel();
  })), this);
  timer_ = g_timeout_source_new(33);
  require(timer_ != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法建立二维码生命周期监督");
  g_source_set_callback(timer_, +[](gpointer data) -> gboolean {
    const auto self = static_cast<QrFlow *>(data)->shared_from_this();
    return self->tick() ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
  }, this, nullptr);
  require(g_source_attach(timer_, ui_context_) != 0, CITIZENSDK_ERROR_UNAVAILABLE, "无法调度二维码窗口");
  gtk_widget_show_all(window_);
  gtk_window_present(GTK_WINDOW(window_));
#else
  throw HostError(CITIZENSDK_ERROR_UNSUPPORTED, "此构建没有原生二维码 UI");
#endif
}

bool QrFlow::session_safe() noexcept {
#if CITIZENSDK_ENABLE_WALLET_UI
  const auto boolean = [](GDBusProxy *proxy, const char *field, bool expected) {
    if (proxy == nullptr) return false;
    gchar *owner = g_dbus_proxy_get_name_owner(proxy);
    const bool owned = owner != nullptr; g_free(owner);
    GVariant *value = g_dbus_proxy_get_cached_property(proxy, field);
    const bool valid = owned && value != nullptr && g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN) &&
        (g_variant_get_boolean(value) != FALSE) == expected;
    if (value != nullptr) g_variant_unref(value);
    return valid;
  };
  if (!boolean(session_, "Active", true) || !boolean(session_, "LockedHint", false) ||
      !boolean(manager_, "PreparingForSleep", false) || !boolean(manager_, "PreparingForShutdown", false)) return false;
  // SDK 的 GTK 设备认证窗口仍是本应用窗口；真正离开应用后不得恢复。
  if (confirmed_ && activated_ && !cancellation_.closing()) {
    GList *windows = gtk_window_list_toplevels();
    bool active = false;
    for (GList *item = windows; item != nullptr; item = item->next)
      if (GTK_IS_WINDOW(item->data) && gtk_window_is_active(GTK_WINDOW(item->data))) active = true;
    g_list_free(windows);
    return active;
  }
  return true;
#else
  return false;
#endif
}
void QrFlow::hide_ui() noexcept {
#if CITIZENSDK_ENABLE_WALLET_UI
  hiding_ = true;
  if (window_ != nullptr) gtk_widget_hide(window_);
  if (image_ != nullptr) gtk_image_clear(GTK_IMAGE(image_));
#endif
}
void QrFlow::destroy_ui() noexcept {
#if CITIZENSDK_ENABLE_WALLET_UI
  hiding_ = true;
  if (timer_ != nullptr) { g_source_destroy(timer_); g_source_unref(timer_); timer_ = nullptr; }
  for (auto **proxy : {&session_, &manager_}) if (*proxy != nullptr) {
    g_signal_handlers_disconnect_by_data(*proxy, this); g_object_unref(*proxy); *proxy = nullptr;
  }
  if (parent_ != nullptr) {
    g_signal_handlers_disconnect_by_data(parent_, this);
    g_object_remove_weak_pointer(G_OBJECT(parent_), reinterpret_cast<gpointer *>(&parent_));
    parent_ = nullptr;
  }
  if (window_ != nullptr) { g_signal_handlers_disconnect_by_data(window_, this); gtk_widget_destroy(window_); window_ = nullptr; }
  image_ = text_ = button_ = nullptr;
  if (ui_context_ != nullptr) { g_main_context_unref(ui_context_); ui_context_ = nullptr; }
#endif
}
void QrFlow::set_review(const std::string &value) {
#if CITIZENSDK_ENABLE_WALLET_UI
  const auto rendered = display_document(value);
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_)), rendered.data(),
                           static_cast<gint>(rendered.size()));
  gtk_widget_set_sensitive(button_, TRUE);
#else
  (void)value;
#endif
}
void QrFlow::set_busy() {
#if CITIZENSDK_ENABLE_WALLET_UI
  gtk_widget_set_sensitive(button_, FALSE);
  gtk_button_set_label(GTK_BUTTON(button_), "正在进行设备认证与签名…");
#endif
}
void QrFlow::preview(const QrFrame &frame) {
#if CITIZENSDK_ENABLE_WALLET_UI
  GdkPixbuf *pixels = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8,
      static_cast<int>(frame.width), static_cast<int>(frame.height));
  require(pixels != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法显示摄像头预览");
  auto *bytes = gdk_pixbuf_get_pixels(pixels);
  const auto stride = static_cast<std::size_t>(gdk_pixbuf_get_rowstride(pixels));
  for (uint32_t y = 0; y < frame.height; ++y)
    for (uint32_t x = 0; x < frame.width; ++x) {
      const auto value = frame.luminance[static_cast<std::size_t>(y) * frame.width + x];
      auto *pixel = bytes + static_cast<std::size_t>(y) * stride + static_cast<std::size_t>(x) * 3;
      pixel[0] = pixel[1] = pixel[2] = value;
    }
  GdkPixbuf *scaled = gdk_pixbuf_scale_simple(pixels, 640, 480, GDK_INTERP_BILINEAR);
  g_object_unref(pixels);
  require(scaled != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "无法缩放摄像头预览");
  gtk_image_set_from_pixbuf(GTK_IMAGE(image_), scaled);
  g_object_unref(scaled);
#else
  (void)frame;
#endif
}

}  // namespace

citizensdk_error_code_t present_qr_flow(
    const std::shared_ptr<HostBridge> &host, std::string sign_request,
    void *context, citizensdk_qr_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle) {
  if (out_handle != nullptr) *out_handle = 0;
  if (!host || completion == nullptr || out_handle == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  if ((host->modules() & CITIZENSDK_MODULE_QR) == 0) return CITIZENSDK_ERROR_UNSUPPORTED;
  if (host->public_sdk() == 0) return CITIZENSDK_ERROR_NOT_READY;
  uint64_t token = 0;
  citizensdk_wallet_flow_handle_t handle = 0;
  try {
    if (!sign_request.empty()) {
      require(sign_request.size() <= 2331, CITIZENSDK_ERROR_INVALID_ARGUMENT, "签名请求超过上限");
      require((host->modules() & (CITIZENSDK_MODULE_CHAIN | CITIZENSDK_MODULE_SIGNING)) ==
              (CITIZENSDK_MODULE_CHAIN | CITIZENSDK_MODULE_SIGNING),
              CITIZENSDK_ERROR_UNSUPPORTED, "安全扫码签名需要链和签名模块");
    }
    token = host->reserve_wallet_flow();
    handle = reserve_wallet_flow_handle();
    auto flow = std::make_shared<QrFlow>(handle, host, token, std::move(sign_request), context, completion);
    { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.emplace(handle, flow); }
    flow->start();
    token = 0; *out_handle = handle;
    return CITIZENSDK_OK;
  } catch (...) {
    { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.erase(handle); }
    if (token != 0) host->finish_wallet_flow(token);
    return map_exception();
  }
}

citizensdk_error_code_t cancel_qr_flow(
    const std::shared_ptr<HostBridge> &host, citizensdk_wallet_flow_handle_t handle) noexcept {
  std::lock_guard<std::mutex> guard(qr_flows_lock);
  const auto found = qr_flows.find(handle);
  if (found == qr_flows.end() || !found->second->belongs_to(host.get()))
    return CITIZENSDK_ERROR_INVALID_HANDLE;
  found->second->cancel();
  return CITIZENSDK_OK;
}
void cancel_host_qr_flows(const HostBridge *host) noexcept {
  std::lock_guard<std::mutex> guard(qr_flows_lock);
  for (const auto &entry : qr_flows) if (entry.second->belongs_to(host)) entry.second->cancel();
}
}  // namespace citizen_sdk::linux
