#include <libstf/util.hpp>

namespace libstf {

void enqueue_stream_input(std::shared_ptr<coyote::cThread> cthread,
                          std::shared_ptr<TLBManager> tlb_manager, const void *ptr, size_t size,
                          stream_t stream, bool last) {
    auto byte_ptr = static_cast<const std::byte *>(ptr);

    // Ensure a TLB entry exists for this data
    tlb_manager->ensure_tlb_mapping(ptr, size);

    // Coyote supports a maximum transfer size
    // -> We create multiple transfers of at most maximum_transfer_size
    for (size_t off = 0; off < size; off += coyote::MAX_TRANSFER_SIZE) {
        // Get the address and output_size of this chunk
        auto curr_ptr   = (void *)(byte_ptr + off);
        auto input_size = std::min(size - off, coyote::MAX_TRANSFER_SIZE);

        // Configure the data transfer
        coyote::localSg sg;
        sg.addr   = curr_ptr;
        sg.len    = input_size;
        sg.stream = coyote::STRM_HOST;
        sg.dest   = stream;

        auto last_transfer = (off + coyote::MAX_TRANSFER_SIZE >= size) && last;
        cthread->invoke(coyote::CoyoteOper::LOCAL_READ, sg, last_transfer);
    }
}

std::string demangle_type_name(const char *mangled) {
    int                                     status;
    std::unique_ptr<char, void (*)(void *)> demangled(
        abi::__cxa_demangle(mangled, nullptr, nullptr, &status), std::free);
    return status == 0 ? demangled.get() : mangled;
}

} // namespace libstf
