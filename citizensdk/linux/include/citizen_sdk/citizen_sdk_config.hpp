#ifndef CITIZENSDK_CPP_CONFIG_HPP
#define CITIZENSDK_CPP_CONFIG_HPP

#include <filesystem>
#include <string>
#include "citizen_sdk/citizensdk_host.h"

namespace citizen_sdk {

struct Config {
  std::filesystem::path storage_root;
  std::filesystem::path asset_root;
  std::string application_id;
  void *gtk_parent_window = nullptr;
  // 唯一模块选择；平台只装配资源，不复制 Rust 的依赖规则。
  uint32_t modules = CITIZENSDK_MODULE_FULL;
};

inline citizensdk_bytes_view_t bytes_view(const std::string &value) noexcept {
  return {reinterpret_cast<const uint8_t *>(value.data()), static_cast<uint64_t>(value.size())};
}

}  // namespace citizen_sdk

#endif
