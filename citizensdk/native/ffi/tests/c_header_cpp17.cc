#include <cstddef>
#include <type_traits>

#include "citizensdk.h"

static_assert(std::is_standard_layout<citizensdk_create_options_t>::value,
              "create must be standard layout");
static_assert(std::is_standard_layout<citizensdk_host_services_v1_t>::value,
              "host services must be standard layout");
static_assert(std::is_standard_layout<citizensdk_history_record_info_t>::value,
              "history record must be standard layout");

/* Compile the exact same 89-symbol, structure, offset and constant assertion
 * table as C++17. The shared translation unit selects C++ type traits for its
 * function signatures; this one spelling adapter covers the direct constant
 * assertions, so neither consumer contract can silently drift. */
#define _Static_assert static_assert
#include "c_header_c11.c"
