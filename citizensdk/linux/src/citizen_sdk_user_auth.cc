#include "citizen_sdk_user_auth.hpp"

#include <chrono>
#include <condition_variable>
#include <cstring>
#include <exception>
#include <memory>
#include <new>
#include <utility>
#include "citizen_sdk_input_limits.hpp"

#if CITIZENSDK_ENABLE_WALLET_UI
#include <gtk/gtk.h>
#endif

namespace citizen_sdk::linux {

#if CITIZENSDK_ENABLE_WALLET_UI
namespace {

struct PromptState final {
  std::mutex lock;
  std::condition_variable ready;
  bool started{false};
  bool done{false};
  bool abandoned{false};
  bool confirmation{false};
  unsigned retirement_wrong_thread_dispatches{0};
  std::thread::id ui_thread;
  GMainContext *ui_context{};
  GtkParentRef *parent{};
  uint64_t host_operation_id{};
  bool private_view_bound{};
  GtkWidget *dialog{};
  GtkWidget *password{};
  GtkWidget *second{};
  GtkWidget *error{};
  AuthenticationResult result;
  ~PromptState() {
    if (ui_context != nullptr) g_main_context_unref(ui_context);
  }
};

void clear_controls(const std::shared_ptr<PromptState> &state) noexcept {
  if (state->password != nullptr) {
    gtk_entry_set_text(GTK_ENTRY(state->password), "");
  }
  if (state->second != nullptr) {
    gtk_entry_set_text(GTK_ENTRY(state->second), "");
  }
}

void destroy_dialog(const std::shared_ptr<PromptState> &state) noexcept {
  clear_controls(state);
  if (state->dialog != nullptr) {
    GtkWidget *dialog = state->dialog;
    state->dialog = nullptr;
    state->password = nullptr;
    state->second = nullptr;
    state->error = nullptr;
    gtk_widget_destroy(dialog);
  }
}

void complete_prompt(const std::shared_ptr<PromptState> &state,
                     citizensdk_error_code_t code,
                     SensitiveBuffer password = {}) noexcept {
  try {
    std::lock_guard<std::mutex> guard(state->lock);
    if (state->done || state->abandoned) {
      password.clear();
      return;
    }
    state->result = {code, std::move(password)};
    state->done = true;
  } catch (...) {
    password.clear();
    std::lock_guard<std::mutex> guard(state->lock);
    state->result.password.clear();
    state->result.code = CITIZENSDK_ERROR_INTERNAL;
    state->done = true;
  }
  state->ready.notify_all();
}

void response_received(GtkDialog *, gint response, gpointer context) noexcept {
  const auto state =
      *static_cast<std::shared_ptr<PromptState> *>(context);
  try {
    bool retired = false;
    {
      std::lock_guard<std::mutex> guard(state->lock);
      retired = state->abandoned || state->done;
    }
    if (retired) { destroy_dialog(state); return; }
    if (response != GTK_RESPONSE_ACCEPT) {
      clear_controls(state);
      complete_prompt(state, CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED);
      destroy_dialog(state);
      return;
    }
    const char *first = gtk_entry_get_text(GTK_ENTRY(state->password));
    const char *second = state->second == nullptr
                             ? first
                             : gtk_entry_get_text(GTK_ENTRY(state->second));
    const std::size_t length = first == nullptr ? 0 : std::strlen(first);
    const bool valid = first != nullptr && length >= 12 &&
        length <= input_limits::kMaximumUnlockPasswordBytes;
    const bool matches = first != nullptr && second != nullptr &&
        std::strcmp(first, second) == 0;
    if (!valid || !matches) {
      gtk_label_set_text(
          GTK_LABEL(state->error),
          !valid ? "口令长度必须为 12...1024 个 UTF-8 字节。"
                 : "两次输入的口令不一致。");
      return;
    }
    SensitiveBuffer password(reinterpret_cast<const uint8_t *>(first), length);
    clear_controls(state);
    complete_prompt(state, CITIZENSDK_OK, std::move(password));
    destroy_dialog(state);
  } catch (...) {
    clear_controls(state);
    complete_prompt(state, CITIZENSDK_ERROR_INTERNAL);
    destroy_dialog(state);
  }
}

void dialog_destroyed(GtkWidget *widget, gpointer context) noexcept {
  const auto state =
      *static_cast<std::shared_ptr<PromptState> *>(context);
  try {
    if (state->dialog != widget) return;
    clear_controls(state);
    state->dialog = nullptr;
    state->password = nullptr;
    state->second = nullptr;
    state->error = nullptr;
    // A parent-window destroy is a real terminal cancellation, never a stale
    // raw-parent dereference or an indefinitely blocked Core worker.
    complete_prompt(state, CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED);
  } catch (...) {
    complete_prompt(state, CITIZENSDK_ERROR_INTERNAL);
  }
}

gboolean build_prompt(gpointer context) noexcept {
  const auto state =
      *static_cast<std::shared_ptr<PromptState> *>(context);
  try {
    {
      std::lock_guard<std::mutex> guard(state->lock);
      state->started = true;
      if (state->abandoned || state->done ||
          std::this_thread::get_id() != state->ui_thread) {
        if (!state->done) {
          state->result.code = CITIZENSDK_ERROR_UNAVAILABLE;
          state->done = true;
        }
        state->ready.notify_all();
        return G_SOURCE_REMOVE;
      }
    }
    state->ready.notify_all();

    GtkParentLease parent = state->parent == nullptr
                                ? GtkParentLease()
                                : state->parent->acquire();
    state->dialog = gtk_dialog_new_with_buttons(
        state->confirmation ? "创建 CitizenSDK 设备金库口令"
                            : "解锁 CitizenSDK 设备金库",
        static_cast<GtkWindow *>(parent.get()),
        static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL |
                                    GTK_DIALOG_DESTROY_WITH_PARENT),
        "取消", GTK_RESPONSE_CANCEL, "继续", GTK_RESPONSE_ACCEPT, nullptr);
    if (state->dialog == nullptr) {
      complete_prompt(state, CITIZENSDK_ERROR_UNAVAILABLE);
      return G_SOURCE_REMOVE;
    }
    // 标记只存在本 SDK 原生对象，操作号来自 Core 真实 unwrap 调用。
    g_object_set_data(G_OBJECT(state->dialog), "citizensdk-authentication", state.get());
    gtk_window_set_resizable(GTK_WINDOW(state->dialog), FALSE);
    GtkWidget *area =
        gtk_dialog_get_content_area(GTK_DIALOG(state->dialog));
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width(GTK_CONTAINER(box), 18);
    gtk_container_add(GTK_CONTAINER(area), box);
    GtkWidget *description = gtk_label_new(
        state->confirmation
            ? "此口令只用于本设备 TPM 金库，不是助记词派生密码。请至少输入 12 个 UTF-8 字节。"
            : "输入本设备 CitizenSDK 金库口令以在 TPM 内解包钱包密钥。");
    gtk_label_set_line_wrap(GTK_LABEL(description), TRUE);
    gtk_label_set_xalign(GTK_LABEL(description), 0.0F);
    gtk_box_pack_start(GTK_BOX(box), description, FALSE, FALSE, 0);
    state->password = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(state->password), FALSE);
    gtk_entry_set_input_purpose(GTK_ENTRY(state->password),
                                GTK_INPUT_PURPOSE_PASSWORD);
    gtk_entry_set_placeholder_text(GTK_ENTRY(state->password),
                                   "设备金库口令");
    gtk_box_pack_start(GTK_BOX(box), state->password, FALSE, FALSE, 0);
    if (state->confirmation) {
      state->second = gtk_entry_new();
      gtk_entry_set_visibility(GTK_ENTRY(state->second), FALSE);
      gtk_entry_set_input_purpose(GTK_ENTRY(state->second),
                                  GTK_INPUT_PURPOSE_PASSWORD);
      gtk_entry_set_placeholder_text(GTK_ENTRY(state->second),
                                     "再次输入设备金库口令");
      gtk_box_pack_start(GTK_BOX(box), state->second, FALSE, FALSE, 0);
    }
    state->error = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(state->error), 0.0F);
    gtk_box_pack_start(GTK_BOX(box), state->error, FALSE, FALSE, 0);

    auto *signal_owner = new std::shared_ptr<PromptState>(state);
    const gulong signal = g_signal_connect_data(
        state->dialog, "response", G_CALLBACK(response_received), signal_owner,
        +[](gpointer owner, GClosure *) noexcept {
          delete static_cast<std::shared_ptr<PromptState> *>(owner);
        }, static_cast<GConnectFlags>(0));
    if (signal == 0) {
      delete signal_owner;
      throw std::bad_alloc();
    }
    auto *destroy_owner = new std::shared_ptr<PromptState>(state);
    const gulong destroy_signal = g_signal_connect_data(
        state->dialog, "destroy", G_CALLBACK(dialog_destroyed), destroy_owner,
        +[](gpointer owner, GClosure *) noexcept {
          delete static_cast<std::shared_ptr<PromptState> *>(owner);
        }, static_cast<GConnectFlags>(0));
    if (destroy_signal == 0) {
      delete destroy_owner;
      throw std::bad_alloc();
    }
    auto *focus_owner = new std::shared_ptr<PromptState>(state);
    const gulong focus_signal = g_signal_connect_data(
        state->dialog, "focus-out-event", G_CALLBACK((+[](GtkWidget *, GdkEventFocus *,
                                                          gpointer context) -> gboolean {
          const auto prompt = *static_cast<std::shared_ptr<PromptState> *>(context);
          if (prompt->private_view_bound && prompt->dialog != nullptr) {
            clear_controls(prompt);
            complete_prompt(prompt, CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED);
            destroy_dialog(prompt);
          }
          return FALSE;
        })), focus_owner, +[](gpointer owner, GClosure *) noexcept {
          delete static_cast<std::shared_ptr<PromptState> *>(owner);
        }, static_cast<GConnectFlags>(0));
    if (focus_signal == 0) { delete focus_owner; throw std::bad_alloc(); }
    gtk_widget_show_all(state->dialog);
  } catch (...) {
    destroy_dialog(state);
    complete_prompt(state, CITIZENSDK_ERROR_INTERNAL);
  }
  return G_SOURCE_REMOVE;
}

gboolean retire_prompt(gpointer context) noexcept {
  const auto state =
      *static_cast<std::shared_ptr<PromptState> *>(context);
  if (std::this_thread::get_id() == state->ui_thread) {
    destroy_dialog(state);
    return G_SOURCE_REMOVE;
  }
  // Do not discard the only UI-thread destruction request if another thread
  // temporarily acquires the context. The abandoned state prevents a late
  // response from copying the password while this source waits for its owner.
  if (++state->retirement_wrong_thread_dispatches >= 8) std::terminate();
  GSource *current = g_main_current_source();
  if (current != nullptr) {
    g_source_set_ready_time(
        current, g_get_monotonic_time() + G_TIME_SPAN_MILLISECOND * 100);
  }
  return G_SOURCE_CONTINUE;
}

bool attach_idle(const std::shared_ptr<PromptState> &state,
                 GSourceFunc callback) noexcept {
  GSource *source = g_idle_source_new();
  if (source == nullptr) return false;
  try {
    auto *owner = new std::shared_ptr<PromptState>(state);
    g_source_set_callback(
        source, callback, owner,
        +[](gpointer context) noexcept {
          delete static_cast<std::shared_ptr<PromptState> *>(context);
        });
    const guint identity = g_source_attach(source, state->ui_context);
    if (identity == 0) g_source_destroy(source);
    g_source_unref(source);
    return identity != 0;
  } catch (...) {
    g_source_destroy(source);
    g_source_unref(source);
    return false;
  }
}

void retire_or_fail_closed(
    const std::shared_ptr<PromptState> &state) noexcept {
  auto delay = std::chrono::milliseconds(1);
  for (unsigned attempt = 0; attempt < 8; ++attempt) {
    if (attach_idle(state, retire_prompt)) return;
    try { std::this_thread::sleep_for(delay); } catch (...) {}
    if (delay < std::chrono::milliseconds(100)) delay *= 2;
  }
  // Returning would leave a password-bearing GTK entry alive with no owner
  // capable of clearing it. Process termination is the deterministic
  // fail-closed boundary for an exhausted UI source allocator/context.
  std::terminate();
}

}  // namespace
#endif

UserAuth::UserAuth(GtkParentRef &parent)
    : parent_(parent), ui_thread_(std::this_thread::get_id()) {
#if CITIZENSDK_ENABLE_WALLET_UI
  // Host construction is the one GTK-thread admission point. Worker-side
  // capability queries only read this frozen result and never call GTK.
  ui_available_ = gtk_init_check(nullptr, nullptr) != FALSE &&
                  gdk_display_get_default() != nullptr;
  if (ui_available_) {
    ui_context_ = g_main_context_ref_thread_default();
    ui_available_ = ui_context_ != nullptr;
  }
#endif
}

UserAuth::~UserAuth() {
#if CITIZENSDK_ENABLE_WALLET_UI
  if (ui_context_ != nullptr) {
    g_main_context_unref(static_cast<GMainContext *>(ui_context_));
    ui_context_ = nullptr;
  }
#endif
}

bool accept_private_key_authentication_window(
    void *window, void *view_window, const void *owner, uint64_t host_operation_id) noexcept {
#if CITIZENSDK_ENABLE_WALLET_UI
  if (window == nullptr || view_window == nullptr || owner == nullptr ||
      host_operation_id == 0) return false;
  auto *state = static_cast<PromptState *>(g_object_get_data(
      G_OBJECT(window), "citizensdk-authentication"));
  if (state == nullptr || state->parent != owner ||
      state->host_operation_id != host_operation_id || state->dialog != window)
    return false;
  gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(view_window));
  state->private_view_bound = true;
  return true;
#else
  (void)window; (void)view_window; (void)owner; (void)host_operation_id;
  return false;
#endif
}

bool UserAuth::available() const noexcept { return ui_available_; }

AuthenticationResult UserAuth::create_vault_password() { return prompt(true, 0); }
AuthenticationResult UserAuth::unlock_vault_password(uint64_t host_operation_id) {
  return prompt(false, host_operation_id);
}

AuthenticationResult UserAuth::prompt(bool confirmation, uint64_t host_operation_id) {
#if !CITIZENSDK_ENABLE_WALLET_UI
  (void)confirmation;
  (void)host_operation_id;
  return {CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, SensitiveBuffer()};
#else
  if (!ui_available_) {
    return {CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, SensitiveBuffer()};
  }
  // Waiting on the GTK owner would deadlock. Core vault operations must run on
  // a worker and never expose the password through a language binding.
  if (std::this_thread::get_id() == ui_thread_) {
    return {CITIZENSDK_ERROR_BUSY, SensitiveBuffer()};
  }
  std::lock_guard<std::mutex> prompt_admission(prompt_lock_);
  const auto state = std::make_shared<PromptState>();
  state->confirmation = confirmation;
  state->ui_thread = ui_thread_;
  state->ui_context =
      g_main_context_ref(static_cast<GMainContext *>(ui_context_));
  state->parent = &parent_;
  state->host_operation_id = host_operation_id;
  if (!attach_idle(state, build_prompt)) {
    return {CITIZENSDK_ERROR_UNAVAILABLE, SensitiveBuffer()};
  }

  std::unique_lock<std::mutex> guard(state->lock);
  if (!state->ready.wait_for(guard, std::chrono::seconds(5),
                             [&] { return state->started; })) {
    state->abandoned = true;
    state->done = true;
    guard.unlock();
    retire_or_fail_closed(state);
    return {CITIZENSDK_ERROR_UNAVAILABLE, SensitiveBuffer()};
  }
  if (!state->ready.wait_for(guard, std::chrono::minutes(5),
                             [&] { return state->done; })) {
    state->abandoned = true;
    state->done = true;
    guard.unlock();
    retire_or_fail_closed(state);
    return {CITIZENSDK_ERROR_TIMEOUT, SensitiveBuffer()};
  }
  return std::move(state->result);
#endif
}

}  // namespace citizen_sdk::linux
