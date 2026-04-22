#pragma once

#include <cstddef>
#include <cxxabi.h>
#include <memory>
#include <string>

#include <coyote/cThread.hpp>

#include <libstf/common.hpp>
#include <libstf/tlb_manager.hpp>

namespace libstf {

/**
 * Non-blocking function that ensures that the given buffer is mapped to the FPGA's TLB and invokes
 * local reads of the maximum Coyote transfer size on the cThread.
 */
void enqueue_stream_input(std::shared_ptr<coyote::cThread> cthread,
                          std::shared_ptr<TLBManager> tlb_manager, const void *ptr, size_t size,
                          stream_t stream, bool last = true);

std::string demangle_type_name(const char *mangled);

} // namespace libstf
