#include <cassert>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <variant>

#include "citizen_sdk/citizen_sdk_plugin.h"
#include "citizen_sdk_flutter_codec.hpp"
#include "citizen_sdk_flutter_sessions.hpp"

#ifdef NDEBUG
#error "CitizenSDK Linux contract assertions must remain enabled"
#endif

namespace citizen_sdk::flutter {
// Hidden native dependency seam, intentionally absent from installed headers.
// The exported registrar entry invokes exactly this implementation with the
// real OS environment and Host; only finite transport dependencies differ.
void register_plugin(FlPluginRegistrar *, EnvironmentFactory, TransportFactory);
}  // namespace citizen_sdk::flutter

namespace csf = citizen_sdk::flutter;

namespace {

typedef struct _FixtureResponseHandle {
  FlBinaryMessengerResponseHandle parent_instance;
  guint attempts;
} FixtureResponseHandle;
typedef struct _FixtureResponseHandleClass {
  FlBinaryMessengerResponseHandleClass parent_class;
} FixtureResponseHandleClass;
static void fixture_response_handle_class_init(FixtureResponseHandleClass *klass);
static void fixture_response_handle_init(FixtureResponseHandle *) {}
G_DEFINE_TYPE(FixtureResponseHandle, fixture_response_handle,
              fl_binary_messenger_response_handle_get_type())

void fixture_response_handle_dispose(GObject *object) {
  // Mirror the documented public messenger ownership rule. An unanswered
  // response dropped during a live channel replacement is a test failure.
  assert(reinterpret_cast<FixtureResponseHandle *>(object)->attempts == 1);
  G_OBJECT_CLASS(fixture_response_handle_parent_class)->dispose(object);
}
void fixture_response_handle_class_init(FixtureResponseHandleClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = fixture_response_handle_dispose;
}

struct Handler final {
  FlBinaryMessengerMessageHandler callback{};
  gpointer data{};
  GDestroyNotify destroy{};
};

typedef struct _FixtureMessenger {
  GObject parent_instance;
  std::map<std::string, Handler> *handlers;
  guint responses;
  guint destroy_depth;
  guint responses_in_destroy;
  gboolean engine_gone;
  GBytes *last_response;
} FixtureMessenger;
typedef struct _FixtureMessengerClass { GObjectClass parent_class; } FixtureMessengerClass;

static void fixture_messenger_interface_init(FlBinaryMessengerInterface *interface);
static void fixture_messenger_class_init(FixtureMessengerClass *klass);
static void fixture_messenger_init(FixtureMessenger *self);
G_DEFINE_TYPE_WITH_CODE(
    FixtureMessenger, fixture_messenger, G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(fl_binary_messenger_get_type(),
                          fixture_messenger_interface_init))

void clear_handlers(FixtureMessenger *self) {
  std::map<std::string, Handler> handlers;
  handlers.swap(*self->handlers);
  for (auto &[_, handler] : handlers) {
    if (handler.destroy != nullptr) {
      ++self->destroy_depth;
      handler.destroy(handler.data);
      --self->destroy_depth;
    }
  }
}

void fixture_messenger_dispose(GObject *object) {
  auto *self = reinterpret_cast<FixtureMessenger *>(object);
  clear_handlers(self);
  g_clear_pointer(&self->last_response, g_bytes_unref);
  G_OBJECT_CLASS(fixture_messenger_parent_class)->dispose(object);
}

void fixture_messenger_finalize(GObject *object) {
  delete reinterpret_cast<FixtureMessenger *>(object)->handlers;
  G_OBJECT_CLASS(fixture_messenger_parent_class)->finalize(object);
}

void fixture_messenger_class_init(FixtureMessengerClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = fixture_messenger_dispose;
  G_OBJECT_CLASS(klass)->finalize = fixture_messenger_finalize;
}

void fixture_messenger_init(FixtureMessenger *self) {
  self->handlers = new std::map<std::string, Handler>();
  self->responses = 0;
}

void set_handler(FlBinaryMessenger *messenger, const gchar *channel,
                 FlBinaryMessengerMessageHandler callback, gpointer data,
                 GDestroyNotify destroy) {
  auto *self = reinterpret_cast<FixtureMessenger *>(messenger);
  auto existing = self->handlers->find(channel);
  if (existing != self->handlers->end()) {
    Handler old = existing->second;
    self->handlers->erase(existing);
    if (old.destroy != nullptr) {
      ++self->destroy_depth;
      old.destroy(old.data);
      --self->destroy_depth;
    }
  }
  if (callback != nullptr) (*self->handlers)[channel] = {callback, data, destroy};
}

gboolean send_response(FlBinaryMessenger *messenger,
                       FlBinaryMessengerResponseHandle *handle,
                       GBytes *bytes, GError **error) {
  auto *self = reinterpret_cast<FixtureMessenger *>(messenger);
  ++self->responses;
  if (self->destroy_depth != 0) ++self->responses_in_destroy;
  ++reinterpret_cast<FixtureResponseHandle *>(handle)->attempts;
  g_clear_pointer(&self->last_response, g_bytes_unref);
  self->last_response = g_bytes_ref(bytes);
  if (self->engine_gone) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_CLOSED,
                        "Fixture engine is gone");
    return FALSE;
  }
  return TRUE;
}
void send_on_channel(FlBinaryMessenger *, const gchar *, GBytes *, GCancellable *,
                     GAsyncReadyCallback, gpointer) {}
GBytes *send_on_channel_finish(FlBinaryMessenger *, GAsyncResult *, GError **) {
  return nullptr;
}
void resize_channel(FlBinaryMessenger *, const gchar *, int64_t) {}
void set_overflow(FlBinaryMessenger *, const gchar *, bool) {}
void shutdown(FlBinaryMessenger *messenger) {
  auto *self = reinterpret_cast<FixtureMessenger *>(messenger);
  self->engine_gone = TRUE;
  clear_handlers(self);
}

void fixture_messenger_interface_init(FlBinaryMessengerInterface *interface) {
  interface->set_message_handler_on_channel = set_handler;
  interface->send_response = send_response;
  interface->send_on_channel = send_on_channel;
  interface->send_on_channel_finish = send_on_channel_finish;
  interface->resize_channel = resize_channel;
  interface->set_warns_on_channel_overflow = set_overflow;
  interface->shutdown = shutdown;
}

typedef struct _FixtureRegistrar {
  GObject parent_instance;
  FixtureMessenger *messenger;
} FixtureRegistrar;
typedef struct _FixtureRegistrarClass { GObjectClass parent_class; } FixtureRegistrarClass;

static void fixture_registrar_interface_init(FlPluginRegistrarInterface *interface);
static void fixture_registrar_class_init(FixtureRegistrarClass *klass);
static void fixture_registrar_init(FixtureRegistrar *self);
G_DEFINE_TYPE_WITH_CODE(
    FixtureRegistrar, fixture_registrar, G_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(fl_plugin_registrar_get_type(),
                          fixture_registrar_interface_init))

void fixture_registrar_dispose(GObject *object) {
  auto *self = reinterpret_cast<FixtureRegistrar *>(object);
  g_clear_object(&self->messenger);
  G_OBJECT_CLASS(fixture_registrar_parent_class)->dispose(object);
}
void fixture_registrar_class_init(FixtureRegistrarClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = fixture_registrar_dispose;
}
void fixture_registrar_init(FixtureRegistrar *self) {
  self->messenger = reinterpret_cast<FixtureMessenger *>(
      g_object_new(fixture_messenger_get_type(), nullptr));
}
FlBinaryMessenger *get_messenger(FlPluginRegistrar *registrar) {
  return FL_BINARY_MESSENGER(
      reinterpret_cast<FixtureRegistrar *>(registrar)->messenger);
}
FlTextureRegistrar *get_texture(FlPluginRegistrar *) { return nullptr; }
FlView *get_view(FlPluginRegistrar *) { return nullptr; }
void fixture_registrar_interface_init(FlPluginRegistrarInterface *interface) {
  interface->get_messenger = get_messenger;
  interface->get_texture_registrar = get_texture;
  interface->get_view = get_view;
}

class PendingTransport final : public csf::NativeTransport {
 public:
  void observe(Observer callback) override { observer = std::move(callback); }
  citizensdk_error_code_t accept(csf::Method method, const csf::DecodedRequest &,
                                 citizensdk_request_id_t *out) override {
    assert(method == csf::Method::get_finalized_head && !accepted);
    accepted = true;
    *out = 41;
    return CITIZENSDK_OK;  // finite accepted request; no actual chain is started
  }
  csf::Value copy_result(csf::Method, citizensdk_result_handle_t) override {
    throw csf::ContractFailure(CITIZENSDK_ERROR_CANCELLED,
                               "Fixture request completed after detach");
  }
  citizensdk_lifecycle_t lifecycle_state() override {
    return CITIZENSDK_LIFECYCLE_CREATED;
  }
  csf::Value genesis_hash() override {
    return csf::Value::string("0x" + std::string(64, '0'));
  }
  csf::Value capability_snapshot() override {
    throw csf::ContractFailure(CITIZENSDK_ERROR_UNAVAILABLE,
                               "Fixture has no chain capabilities");
  }
  void cancel(citizensdk_request_id_t) override { assert(false); }
  csf::WalletCancellation present(
      const csf::DecodedRequest &,
      citizen_sdk::WalletFlowCompletion) override {
    assert(false);
    return {};
  }
  void close() override { assert(false); }
  void retire() noexcept override { ++retired; }
  void complete_after_detach() {
    assert(accepted && !completed);
    completed = true;
    citizensdk_event_t event{};
    event.struct_size = sizeof(event);
    event.abi_version = CITIZENSDK_ABI_VERSION;
    event.event_type = CITIZENSDK_EVENT_REQUEST_COMPLETED;
    event.request_id = 41;
    // This fixture token is never dereferenced or passed to Core. The injected
    // copy_result raises a terminal error; no fabricated successful result.
    event.result = 42;
    observer(event);
  }

  Observer observer;
  bool accepted{};
  bool completed{};
  guint retired{};
};

void drain_context(GMainContext *context) {
  while (g_main_context_pending(context)) g_main_context_iteration(context, FALSE);
}

FlBinaryMessengerResponseHandle *send_method(
    FixtureRegistrar *registrar, const char *name, csf::Value arguments) {
  g_autoptr(FlStandardMethodCodec) codec = csf::new_method_codec();
  auto args = csf::to_fl_value(arguments);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GBytes) message = fl_method_codec_encode_method_call(
      FL_METHOD_CODEC(codec), name, args.get(), &error);
  assert(message != nullptr && error == nullptr);
  auto *response = FL_BINARY_MESSENGER_RESPONSE_HANDLE(
      g_object_new(fixture_response_handle_get_type(), nullptr));
  const Handler handler = registrar->messenger->handlers->at(csf::kMethodChannel);
  handler.callback(FL_BINARY_MESSENGER(registrar->messenger), csf::kMethodChannel,
                    message, response, handler.data);
  return response;
}

void observe_release(GObject *object, bool *alive) {
  *alive = true;
  g_object_weak_ref(object, [](gpointer data, GObject *) {
    *static_cast<bool *>(data) = false;
  }, alive);
}

void replacement_handler(FlBinaryMessenger *, const gchar *, GBytes *,
                         FlBinaryMessengerResponseHandle *, gpointer) {
  assert(false);  // replacement must remain registered, but receives no call
}

void pending_detach_contract(GMainContext *context, bool engine_gone) {
  auto *registrar = reinterpret_cast<FixtureRegistrar *>(
      g_object_new(fixture_registrar_get_type(), nullptr));
  auto native = std::make_shared<PendingTransport>();
  csf::register_plugin(FL_PLUGIN_REGISTRAR(registrar),
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [native](const citizen_sdk::Config &) { return native; });
  auto *opened = send_method(registrar, "open",
                             csf::Value::list({csf::Value::integer(1), csf::Value::integer(63)}));
  assert(registrar->messenger->responses == 1);
  bool opened_alive = true;
  observe_release(G_OBJECT(opened), &opened_alive);
  g_object_unref(opened);
  assert(!opened_alive);  // normal completion removes pending ownership

  g_autoptr(FlStandardMethodCodec) codec = csf::new_method_codec();
  g_autoptr(GError) decode_error = nullptr;
  g_autoptr(FlMethodResponse) open_reply = fl_method_codec_decode_response(
      FL_METHOD_CODEC(codec), registrar->messenger->last_response, &decode_error);
  assert(decode_error == nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(open_reply));
  auto open_value = csf::from_fl_value(fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(open_reply)));
  const std::string session = std::get<std::string>(
      std::get<csf::Value::List>(open_value.data).at(1).data);

  auto *pending = send_method(registrar, "getFinalizedHead", csf::Value::list({
      csf::Value::integer(1), csf::Value::string(session), csf::Value::integer(1)}));
  assert(native->accepted && registrar->messenger->responses == 1);
  bool pending_alive = true;
  observe_release(G_OBJECT(pending), &pending_alive);
  g_object_unref(pending);
  assert(pending_alive);

  auto *messenger = FL_BINARY_MESSENGER(registrar->messenger);
  if (engine_gone) {
    FL_BINARY_MESSENGER_GET_IFACE(messenger)->shutdown(messenger);
  } else {
    // Replacing a channel on a LIVE messenger invokes the same destroy notify
    // as shutdown. It must not drop this already accepted response handle.
    fl_binary_messenger_set_message_handler_on_channel(
        messenger, csf::kMethodChannel, replacement_handler, nullptr, nullptr);
  }
  assert(pending_alive && registrar->messenger->responses == 1);
  assert(registrar->messenger->responses_in_destroy == 0);
  drain_context(context);
  assert(!pending_alive && registrar->messenger->responses == 2);
  assert(registrar->messenger->responses_in_destroy == 0);

  g_autoptr(FlMethodResponse) detached_reply = fl_method_codec_decode_response(
      FL_METHOD_CODEC(codec), registrar->messenger->last_response, &decode_error);
  assert(decode_error == nullptr && FL_IS_METHOD_ERROR_RESPONSE(detached_reply));
  auto *error_reply = FL_METHOD_ERROR_RESPONSE(detached_reply);
  assert(std::string(fl_method_error_response_get_code(error_reply)) ==
         "citizensdk.invalidState");
  const auto details = csf::from_fl_value(fl_method_error_response_get_details(error_reply));
  const auto &fields = std::get<csf::Value::List>(details.data);
  assert(fields.size() == 7);
  assert(std::get<std::string>(fields.at(1).data) == session);
  assert(std::get<int64_t>(fields.at(2).data) == 1);
  assert(std::get<int64_t>(fields.at(3).data) == CITIZENSDK_ERROR_INVALID_STATE);
  assert(std::get<int64_t>(fields.at(4).data) == CITIZENSDK_FAILURE_STAGE_ADMISSION);
  assert(std::get<std::string>(fields.at(5).data) == "getCapabilities");
  if (!engine_gone) {
    assert(registrar->messenger->handlers->at(csf::kMethodChannel).callback ==
           replacement_handler);
    assert(registrar->messenger->handlers->count(csf::kEventChannel) == 0);
    assert(registrar->messenger->handlers->size() == 1);
  } else {
    assert(registrar->messenger->handlers->empty());
  }

  // Native ownership still drains after Flutter teardown, but its late
  // completion must neither reply twice nor revive the detached messenger.
  native->complete_after_detach();
  drain_context(context);
  assert(native->retired == 1 && registrar->messenger->responses == 2);
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->shutdown(messenger);
  drain_context(context);
  assert(registrar->messenger->responses == 2);
  g_object_unref(registrar);
}

void test_stateless_verification(GMainContext *context) {
  auto *registrar = reinterpret_cast<FixtureRegistrar *>(
      g_object_new(fixture_registrar_get_type(), nullptr));
  int environments = 0;
  int transports = 0;
  csf::register_plugin(FL_PLUGIN_REGISTRAR(registrar),
      [&](uint32_t) { ++environments; return csf::OpenEnvironment{}; },
      [&](const citizen_sdk::Config &) {
        ++transports; return std::make_shared<PendingTransport>();
      });
  csf::Value::Bytes signature(64);
  signature.back() = 0x80;
  g_autoptr(FlStandardMethodCodec) codec = csf::new_method_codec();
  for (const bool valid_shape : {true, false}) {
    if (!valid_shape) signature.pop_back();
    auto *response = send_method(registrar, "verifySignature", csf::Value::list({
        csf::Value::integer(1), csf::Value::string("0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972"),
        csf::Value::bytes(signature), csf::Value::bytes({})}));
    g_object_unref(response);
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlMethodResponse) reply = fl_method_codec_decode_response(
        FL_METHOD_CODEC(codec), registrar->messenger->last_response, &error);
    assert(error == nullptr);
    if (valid_shape) {
      assert(FL_IS_METHOD_SUCCESS_RESPONSE(reply));
      const auto result = csf::from_fl_value(fl_method_success_response_get_result(
          FL_METHOD_SUCCESS_RESPONSE(reply)));
      const auto &values = std::get<csf::Value::List>(result.data);
      assert(values.size() == 2 && !std::get<bool>(values[1].data));
    } else {
      assert(FL_IS_METHOD_ERROR_RESPONSE(reply));
      auto *failure = FL_METHOD_ERROR_RESPONSE(reply);
      assert(std::string(fl_method_error_response_get_code(failure)) ==
             "citizensdk.invalidArgument");
      const auto details = csf::from_fl_value(fl_method_error_response_get_details(failure));
      const auto &values = std::get<csf::Value::List>(details.data);
      assert(std::holds_alternative<std::monostate>(values[1].data));
      assert(std::holds_alternative<std::monostate>(values[2].data));
    }
  }
  // 未 open 或 listen；公开纯验签不得触及环境/Host 工厂。
  assert(environments == 0 && transports == 0 && registrar->messenger->responses == 2);
  auto *messenger = FL_BINARY_MESSENGER(registrar->messenger);
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->shutdown(messenger);
  drain_context(context);
  g_object_unref(registrar);
}

}  // namespace

int main() {
  GMainContext *context = g_main_context_default();
  assert(g_main_context_acquire(context));
  test_stateless_verification(context);
  auto *registrar = reinterpret_cast<FixtureRegistrar *>(
      g_object_new(fixture_registrar_get_type(), nullptr));
  citizen_sdk_plugin_register_with_registrar(FL_PLUGIN_REGISTRAR(registrar));
  assert(registrar->messenger->handlers->count(
             citizen_sdk::flutter::kMethodChannel) == 1);
  assert(registrar->messenger->handlers->count(
             citizen_sdk::flutter::kEventChannel) == 1);

  // Drive a real MethodChannel request through production codec/plugin/session
  // code. The unavailable fixture bundle makes open fail synchronously; it must
  // still settle exactly one reply and remove that completed pending call.
  auto method = citizen_sdk::flutter::new_method_codec();
  g_autoptr(FlValue) open_args = fl_value_new_list();
  fl_value_append_take(open_args, fl_value_new_int(1));
  fl_value_append_take(open_args, fl_value_new_int(31));
  g_autoptr(GError) encode_error = nullptr;
  g_autoptr(GBytes) message = fl_method_codec_encode_method_call(
      FL_METHOD_CODEC(method), "open", open_args, &encode_error);
  assert(message != nullptr && encode_error == nullptr);
  auto *response = FL_BINARY_MESSENGER_RESPONSE_HANDLE(
      g_object_new(fixture_response_handle_get_type(), nullptr));
  Handler method_handler = registrar->messenger->handlers->at(
      citizen_sdk::flutter::kMethodChannel);
  method_handler.callback(FL_BINARY_MESSENGER(registrar->messenger),
                          citizen_sdk::flutter::kMethodChannel, message,
                          response, method_handler.data);
  assert(registrar->messenger->responses == 1);
  g_object_unref(response);
  g_object_unref(method);

  // Real messenger shutdown destroys both channel registrations. The first
  // callback must revoke sessions, while deferred cleanup prevents re-entering
  // Flutter before it has cleared the old handler's user_data.
  // shutdown 由公开 messenger interface 提供；不调用 Flutter engine 私有辅助函数。
  auto *messenger = FL_BINARY_MESSENGER(registrar->messenger);
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->shutdown(messenger);
  assert(registrar->messenger->handlers->empty());
  assert(registrar->messenger->responses == 1);
  drain_context(context);
  g_object_unref(registrar);
  pending_detach_contract(context, false);
  pending_detach_contract(context, true);
  g_main_context_release(context);
  return 0;
}
