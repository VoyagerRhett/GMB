// 冻结 Windows Host 自有薄 ABI；根产品 ABI 仍是唯一 Core 合同。
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <regex>
#include <set>
#include <string>
#include <type_traits>
#include <thread>
#include <windows.h>

#include "citizen_sdk/citizensdk_host.h"
#include "citizen_sdk/citizen_sdk.hpp"
#include "citizen_sdk_test_support.hpp"

#ifndef CITIZENSDK_WINDOWS_TEST_SOURCE_DIR
#error "CITIZENSDK_WINDOWS_TEST_SOURCE_DIR must point at the Windows source root"
#endif
#ifdef NDEBUG
#error "CitizenSDK Windows contract assertions must remain enabled"
#endif

int main() {

  static_assert(CITIZENSDK_ABI_VERSION == 1);
  static_assert(CITIZENSDK_CAPABILITY_COUNT == 10);
  static_assert(CITIZENSDK_HOST_ABI_VERSION == 1);
  static_assert(sizeof(citizensdk_handle_t) == sizeof(uint64_t));
  static_assert(sizeof(citizensdk_host_handle_t) == sizeof(uint64_t));
  static_assert(sizeof(citizensdk_wallet_flow_handle_t) == sizeof(uint64_t));
  static_assert(std::is_standard_layout_v<citizensdk_host_config_v1_t>);
  static_assert(std::is_standard_layout_v<citizensdk_wallet_flow_request_v1_t>);
  static_assert(std::is_standard_layout_v<citizensdk_wallet_flow_result_v1_t>);
  static_assert(sizeof(citizensdk_host_config_v1_t) == 72);
  static_assert(offsetof(citizensdk_host_config_v1_t, struct_size) == 0);
  static_assert(offsetof(citizensdk_host_config_v1_t, abi_version) == 4);
  static_assert(offsetof(citizensdk_host_config_v1_t, storage_root_utf8) == 8);
  static_assert(offsetof(citizensdk_host_config_v1_t, asset_root_utf8) == 24);
  static_assert(offsetof(citizensdk_host_config_v1_t, application_id_utf8) ==
                40);
  static_assert(offsetof(citizensdk_host_config_v1_t, hwnd) == 56);
  static_assert(offsetof(citizensdk_host_config_v1_t, enable_wallet) == 64);
  static_assert(offsetof(citizensdk_host_config_v1_t, reserved) == 65);
  static_assert(
      sizeof(static_cast<citizensdk_host_config_v1_t *>(nullptr)->reserved) ==
      7);
  static_assert(sizeof(citizensdk_wallet_flow_request_v1_t) == 32);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t, struct_size) == 0);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t, abi_version) == 4);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t, kind) == 8);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t, word_count) == 12);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t, account_indices) ==
                16);
  static_assert(offsetof(citizensdk_wallet_flow_request_v1_t,
                         account_index_count) == 24);
  static_assert(sizeof(citizensdk_wallet_flow_result_v1_t) == 16);
  static_assert(offsetof(citizensdk_wallet_flow_result_v1_t, struct_size) == 0);
  static_assert(offsetof(citizensdk_wallet_flow_result_v1_t, abi_version) == 4);
  static_assert(offsetof(citizensdk_wallet_flow_result_v1_t, status) == 8);
  static_assert(offsetof(citizensdk_wallet_flow_result_v1_t, error_code) == 12);

  assert(citizensdk_abi_version() == CITIZENSDK_ABI_VERSION);
  assert(citizensdk_host_abi_version() == CITIZENSDK_HOST_ABI_VERSION);
  assert(citizensdk_host_config_size() == sizeof(citizensdk_host_config_v1_t));
  assert(CITIZENSDK_WALLET_FLOW_CREATE == 1);
  assert(CITIZENSDK_WALLET_FLOW_IMPORT == 2);
  assert(CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS == 3);
  assert(CITIZENSDK_WALLET_FLOW_COMPLETED == 1);
  assert(CITIZENSDK_WALLET_FLOW_CANCELLED == 2);
  assert(CITIZENSDK_WALLET_FLOW_FAILED == 3);
  assert(CITIZENSDK_ERROR_CANCELLED == 22);

  const std::string header_path =
      std::string(CITIZENSDK_WINDOWS_TEST_SOURCE_DIR) +
      "/include/citizen_sdk/citizensdk_host.h";
  std::ifstream stream(header_path, std::ios::binary);
  assert(stream.good());
  const std::string header((std::istreambuf_iterator<char>(stream)),
                           std::istreambuf_iterator<char>());
  assert(header.find("citizensdk_linux_host_") == std::string::npos);
  const std::regex function_pattern(R"(\b(citizensdk_host_[a-z0-9_]+)\s*\()",
                                    std::regex::ECMAScript);
  std::set<std::string> functions;
  for (auto iterator = std::sregex_iterator(header.begin(), header.end(),
                                             function_pattern);
       iterator != std::sregex_iterator(); ++iterator) {
    functions.insert((*iterator)[1].str());
  }
  const std::set<std::string> expected{
      "citizensdk_host_abi_version",
      "citizensdk_host_abandon",
      "citizensdk_host_cancel_wallet_flow",
      "citizensdk_host_config_size",
      "citizensdk_host_create",
      "citizensdk_host_create_with_modules",
      "citizensdk_host_create_sdk",
      "citizensdk_host_destroy",
      "citizensdk_host_last_error_copy",
      "citizensdk_host_present_wallet_flow",
      "citizensdk_host_view_account_private_key",
      "citizensdk_host_scan_qr",
      "citizensdk_host_sign_qr_request",
      "citizensdk_host_sdk",
      "citizensdk_host_set_event_callback",
      "citizensdk_host_set_parent_window",
      "citizensdk_host_vault_availability",
  };
  assert(functions == expected);

  // 安装投影必须继续只暴露 CitizenSDK::Host，并由该目标通过安装期
  // CitizenSDK::Core 传递唯一 Core；不能把构建树 imported target 名或
  // 测试专用资产宏泄漏到已安装消费者合同。
  const auto read_source = [](const char *relative) {
    const std::string path = std::string(CITIZENSDK_WINDOWS_TEST_SOURCE_DIR) +
                             relative;
    std::ifstream input(path, std::ios::binary);
    assert(input.good());
    return std::string((std::istreambuf_iterator<char>(input)),
                       std::istreambuf_iterator<char>());
  };
  const std::string cmake = read_source("/CMakeLists.txt");
  // 标准 C++ 与唯一安装依赖方向不能随平台变化。
  assert(cmake.find("set(CMAKE_CXX_EXTENSIONS OFF)") != std::string::npos);
  assert(cmake.find("$<BUILD_INTERFACE:citizensdk_core>") !=
         std::string::npos);
  assert(cmake.find("$<INSTALL_INTERFACE:CitizenSDK::Core>") !=
         std::string::npos);
  assert(cmake.find("EXPORT_NAME Host") != std::string::npos);
  assert(cmake.find("CITIZENSDK_PACKAGED_ASSET_DIR") == std::string::npos);
  const std::string package_config =
      read_source("/cmake/CitizenSDKConfig.cmake.in");
  assert(package_config.find("set(CITIZENSDK_ASSET_DIR") !=
         std::string::npos);
  assert(package_config.find("add_library(CitizenSDK::Core SHARED IMPORTED)") !=
         std::string::npos);
  assert(package_config.find("CitizenSDKDependencies.cmake") !=
         std::string::npos);
  assert(package_config.find("CitizenSDKTargets.cmake") !=
         std::string::npos);
  const std::string test_cmake = read_source("/test/CMakeLists.txt");
  assert(test_cmake.find("set(CITIZENSDK_TEST_WORK_DIR \"\" CACHE PATH") !=
         std::string::npos);
  assert(test_cmake.find(
             "ENVIRONMENT \"CITIZENSDK_TEST_WORK_DIR=${CITIZENSDK_TEST_WORK_DIR}\"") !=
         std::string::npos);
  const std::string test_support =
      read_source("/test/citizen_sdk_test_support.hpp");
  assert(test_support.find("std::getenv(\"CITIZENSDK_TEST_WORK_DIR\")") !=
         std::string::npos);
  assert(test_support.find("BCryptGenRandom") != std::string::npos);
  assert(test_support.find("temp_directory_path") == std::string::npos);
  assert(test_support.find("remove_all") == std::string::npos);

  citizensdk_host_handle_t host = 99;
  assert(citizensdk_host_create(nullptr, nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_create(nullptr, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  citizensdk_host_config_v1_t invalid{};
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);

  citizen_sdk::windows::test::TempDirectory temporary("api-contract");
  const std::string storage = (temporary.path() / "state").u8string();
  const std::string assets = (temporary.path() / "assets").u8string();
  const std::string application_id = "org.citizen.fixture";
  const auto view = [](const std::string &value) {
    return citizensdk_bytes_view_t{
        reinterpret_cast<const uint8_t *>(value.data()),
        static_cast<uint64_t>(value.size())};
  };
  invalid.struct_size = sizeof(invalid);
  invalid.abi_version = CITIZENSDK_HOST_ABI_VERSION;
  invalid.storage_root_utf8 = view(storage);
  invalid.asset_root_utf8 = view(assets);
  invalid.application_id_utf8 = view(application_id);
  invalid.abi_version = CITIZENSDK_HOST_ABI_VERSION + 1;
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  invalid.abi_version = CITIZENSDK_HOST_ABI_VERSION;
  invalid.reserved[0] = 1;
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  invalid.reserved[0] = 0;
  invalid.enable_wallet = 2;
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  invalid.enable_wallet = 0;
  invalid.application_id_utf8 = {nullptr, 0};
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  const std::string invalid_application_id = "Citizen.App";
  invalid.application_id_utf8 = view(invalid_application_id);
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  const std::string relative_storage = "relative-state";
  invalid.application_id_utf8 = view(application_id);
  invalid.storage_root_utf8 = view(relative_storage);
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  const std::string relative_assets = "relative-assets";
  invalid.storage_root_utf8 = view(storage);
  invalid.asset_root_utf8 = view(relative_assets);
  assert(citizensdk_host_create(&invalid, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  uint64_t error_bytes = 0;
  assert(citizensdk_host_last_error_copy(nullptr, 0, &error_bytes) ==
         CITIZENSDK_OK);
  assert(error_bytes > 0);
  std::string copied_error(static_cast<std::size_t>(error_bytes), '\0');
  assert(citizensdk_host_last_error_copy(
             reinterpret_cast<uint8_t *>(copied_error.data()),
             error_bytes - 1, &error_bytes) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_last_error_copy(
             reinterpret_cast<uint8_t *>(copied_error.data()), error_bytes,
             &error_bytes) == CITIZENSDK_OK);
  assert(!copied_error.empty());
  assert(citizensdk_host_sdk(0, nullptr) == CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_destroy(0) == CITIZENSDK_ERROR_INVALID_HANDLE);
  assert(citizensdk_host_abandon(0) == CITIZENSDK_ERROR_INVALID_HANDLE);
  assert(citizensdk_host_last_error_copy(nullptr, 0, nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);

  // Host 构造只组合平台资源；Core 创建保持显式。这个有效的 chain-only
  // 实例无需真实链资产即可冻结未打开、能力查询和正常销毁的 C 生命周期。
  invalid.asset_root_utf8 = view(assets);
  assert(citizensdk_host_create_with_modules(&invalid, 0, &host) == CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  assert(citizensdk_host_create_with_modules(&invalid, CITIZENSDK_MODULE_HISTORY, &host) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(host == 0);
  // 未知/缺依赖模块在平台资源创建前被 Rust 拒绝。
  assert(!std::filesystem::exists(
      temporary.path() / "state" / application_id / "citizensdk"));
  assert(citizensdk_host_create(&invalid, &host) == CITIZENSDK_OK);
  assert(host != 0);
  assert(std::filesystem::is_directory(
      temporary.path() / "state" / application_id / "citizensdk" / "v1" /
      "public"));
  assert(!std::filesystem::exists(
      temporary.path() / "state" / application_id / "citizensdk" / "v1" /
      "secure"));
  assert(!std::filesystem::exists(
      temporary.path() / "state" / application_id / "citizenapp"));
  citizensdk_handle_t sdk = 99;
  assert(citizensdk_host_sdk(host, nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_sdk(host, &sdk) == CITIZENSDK_ERROR_NOT_READY);
  assert(sdk == 0);
  citizensdk_host_vault_availability_t availability{};
  assert(citizensdk_host_vault_availability(host, nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_vault_availability(host, &availability) ==
         CITIZENSDK_OK);
  assert(availability == CITIZENSDK_HOST_VAULT_UNSUPPORTED);
  assert(citizensdk_host_set_event_callback(host, nullptr, nullptr) ==
         CITIZENSDK_OK);
  assert(citizensdk_host_set_parent_window(host, nullptr) == CITIZENSDK_OK);
  assert(citizensdk_host_create_sdk(host, nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(citizensdk_host_create_sdk(host, &sdk) ==
         CITIZENSDK_ERROR_INTEGRITY);
  assert(sdk == 0);
  assert(citizensdk_host_present_wallet_flow(host, nullptr, nullptr, nullptr,
                                             nullptr) ==
         CITIZENSDK_ERROR_INVALID_ARGUMENT);
  citizensdk_account_id_t viewed_account{};
  citizensdk_wallet_flow_handle_t viewed_flow = 99;
  const auto view_complete = +[](void *, const citizensdk_wallet_flow_result_v1_t *) {
    assert(false);  // 未选择 wallet 的拒绝不得接纳回调或触碰金库。
  };
  assert(citizensdk_host_view_account_private_key(host, nullptr, nullptr, view_complete,
                                                  &viewed_flow) == CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(viewed_flow == 0);
  assert(citizensdk_host_view_account_private_key(host, &viewed_account, nullptr, view_complete,
                                                  &viewed_flow) == CITIZENSDK_ERROR_UNSUPPORTED);
  assert(viewed_flow == 0);
  assert(citizensdk_host_cancel_wallet_flow(host, 1) ==
         CITIZENSDK_ERROR_INVALID_HANDLE);
  assert(citizensdk_host_destroy(host) == CITIZENSDK_OK);
  assert(citizensdk_host_destroy(host) == CITIZENSDK_ERROR_INVALID_HANDLE);

  // 钱包与签名均能脱离链独立创建，空资产根不被读取，也不创建公开链数据库。
  for (const auto modules : {CITIZENSDK_MODULE_WALLET, CITIZENSDK_MODULE_SIGNING}) {
    const std::string isolated_id = modules == CITIZENSDK_MODULE_WALLET
        ? "org.citizen.walletfixture" : "org.citizen.signingfixture";
    invalid.application_id_utf8 = view(isolated_id);
    invalid.asset_root_utf8 = {nullptr, 0};
    invalid.enable_wallet = 1;
    assert(citizensdk_host_create_with_modules(&invalid, modules, &host) == CITIZENSDK_OK);
    assert(!std::filesystem::exists(
        temporary.path() / "state" / isolated_id / "citizensdk" / "v1" / "public"));
    assert(citizensdk_host_create_sdk(host, &sdk) == CITIZENSDK_OK && sdk != 0);
    citizensdk_capability_snapshot_t snapshot{};
    snapshot.struct_size = sizeof(snapshot); snapshot.abi_version = CITIZENSDK_ABI_VERSION;
    assert(citizensdk_get_capabilities(sdk, &snapshot) == CITIZENSDK_OK);
    // 金库可用性仍由设备事实报告，不能为通过测试打开软件金库。
    assert(!std::filesystem::exists(
        temporary.path() / "state" / isolated_id / "citizensdk" / "v1" / "public"));
    if (modules == CITIZENSDK_MODULE_SIGNING) {
      assert(citizensdk_host_view_account_private_key(host, &viewed_account, nullptr, view_complete,
                                                      &viewed_flow) == CITIZENSDK_ERROR_UNSUPPORTED);
      assert(viewed_flow == 0);
    }
    assert(citizensdk_host_destroy(host) == CITIZENSDK_OK);
  }

  // 真实 Core 已销毁而 UI 退休仍 BUSY 时，C++ 层必须可重试且不保留旧 handle。
  citizen_sdk::Config cpp_config;
  cpp_config.storage_root = temporary.path() / "cpp-state";
  cpp_config.asset_root = std::filesystem::path(CITIZENSDK_WINDOWS_TEST_SOURCE_DIR).parent_path() /
                          "assets" / "citizenchain";
  cpp_config.application_id = "org.citizen.closefixture";
  citizen_sdk::Host cpp_host(cpp_config);
  cpp_host.open();
  bool worker_busy = false;
  std::thread closer([&] {
    try { cpp_host.close(); }
    catch (const citizen_sdk::Error &error) { worker_busy = error.code() == CITIZENSDK_ERROR_BUSY; }
  });
  closer.join();
  assert(worker_busy);
  assert(cpp_host.native_handle() == 0);
  MSG queued{};
  while (PeekMessageW(&queued, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&queued);
    DispatchMessageW(&queued);
  }
  cpp_host.close();
  assert(cpp_host.host_handle() == 0);
  return 0;
}
