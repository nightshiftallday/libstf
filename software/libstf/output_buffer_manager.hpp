#pragma once

#include <queue>
#include <vector>

#include <coyote/cThread.hpp>

#include <libstf/common.hpp>
#include <libstf/configuration.hpp>
#include <libstf/memory_pool.hpp>
#include <libstf/output_handle.hpp>
#include <libstf/tlb_manager.hpp>

namespace libstf {

class OutputBufferManager {
  public:
    /**
     * Creates a new output buffer manager. The manager is responsible for managing buffers for any
     * output produced by the FPGA. This implementation relies on CSR registers and interrupts
     * that tell the OutputBufferManager how much memory was written by the FPGA.
     *
     * The buffer capacity can influence the performance of the FPGA-initiated transfers
     * and the memory footprint of the OutputBufferManager.
     *
     * @param cthread
     * @param mem_config
     * @param memory_pool
     * @param tlb_manager
     * @param managed_streams Bitmask of streams whose buffers are auto-managed (allocated up front
     *                        via the mask-based acquire_output_handle). Streams with their bit
     *                        cleared must instead use acquire_output_handle(stream, size), where the
     *                        caller supplies the exact transfer size. Default: all streams managed.
     * @param num_buffers_to_enqueue
     * @param buffer_capacity
     */
    OutputBufferManager(std::shared_ptr<coyote::cThread> cthread,
                        std::shared_ptr<MemConfig>  mem_config,
                        std::shared_ptr<MemoryPool> memory_pool,
                        std::shared_ptr<TLBManager> tlb_manager,
                        stream_mask_t managed_streams        = ~stream_mask_t(0),
                        size_t        num_buffers_to_enqueue = 2,
                        size_t        buffer_capacity        = MAXIMUM_OUTPUT_WRITER_BUFFER_SIZE);

    ~OutputBufferManager();

    /**
     * Function that should be invoked whenever an interrupt from the FPGA is captured
     * via the coyote::cThread.
     * @param value The value of the interrupt
     */
    void handle_fpga_interrupt(int value);

    /**
     * Indicates that a set of streams providedby the provided mask will receive at least one data
     * beat from your design. This can also be an empty data beat (e.g. keep all 0 and last = 1). It
     * returns a handle that the data can be retrieved from eventually. The method may be called
     * multiple times to essentially enqueue multiple output stream sets.
     *
     * All streams in `active_streams` must be managed streams (bit set in `managed_streams` passed
     * to the constructor). Unmanaged streams must use the size-based overload below.
     *
     * @param active_streams A mask of the streams to wait on for output. Only the first NUM_STREAMS
     * bits may be set.
     * @return A handle to read the data from.
     */
    std::shared_ptr<OutputHandle> acquire_output_handle(stream_mask_t active_streams);

    /**
     * Acquires an output handle for a single unmanaged stream whose total output size is known up
     * front. Buffers totaling exactly `size` bytes are allocated and enqueued — no extra
     * speculative buffers beyond what is needed for the requested transfer.
     *
     * If `size` exceeds the maximum per-buffer capacity (MAXIMUM_OUTPUT_WRITER_BUFFER_SIZE), the
     * transfer is split across multiple buffers of up to that capacity each. Each chunk is
     * enqueued separately and surfaced to the returned handle via the regular interrupt path, so
     * callers retrieving output via `get_next_stream_output` may see more than one Buffer.
     *
     * The stream must NOT be managed (bit cleared in `managed_streams` passed to the constructor).
     *
     * @param stream The stream to acquire the handle for.
     * @param size   The exact number of bytes the FPGA will write to this stream.
     * @return A handle to read the data from.
     */
    std::shared_ptr<OutputHandle> acquire_output_handle(stream_t stream, size_t size);

    /**
     * Flushes all currently enqueued buffers in hardware. This is necessary after the software is
     * done because it leaves behind stale buffers.
     */
    void flush_buffers();

    /**
     * @return The address of the buffer the FPGA will write next on `stream`, i.e. the one at the
     *         head of that stream's enqueued queue.
     *
     * Needed by designs where the hardware has to be told up front where its output will land.
     * ParCore's string heap is the motivating case: the decoder embeds absolute addresses into the
     * decoded german_str_t records, so the heap base must be known before the column chunk
     * configuration is written.
     *
     * Only meaningful immediately after acquiring a handle for a stream that has exactly one
     * outstanding handle. With several in flight, the head of the queue belongs to an earlier
     * handle rather than the one just acquired.
     *
     * @throws std::runtime_error if no buffer is currently enqueued for the stream.
     */
    void *next_buffer_address(stream_t stream);

    size_t buffer_capacity() const { return BUFFER_CAPACITY; }

    size_t num_streams() const { return NUM_STREAMS; }
    size_t num_buffers_to_enqueue() const { return NUM_BUFFERS_TO_ENQUEUE; }

    /**
     * Diagnostics. Buffers the FPGA has not yet reported back on for `stream`
     * -- the depth the hardware is being kept topped up to. If this drifts
     * towards zero the FPGA is about to run out of somewhere to write, which
     * looks from the outside like the design hanging.
     */
    struct StreamStats {
        size_t enqueued_now;    // currently outstanding
        size_t enqueued_total;  // handed to the FPGA over the run
        size_t interrupts;      // completions reported back
        size_t bytes_written;   // as reported by those completions
    };

    StreamStats stats(stream_t stream);

  private:
    // We need to pass these because otherwise we will get a circular dependency to the
    // CelerisContext
    std::shared_ptr<coyote::cThread> cthread;
    std::shared_ptr<MemConfig>       mem_config;
    std::shared_ptr<MemoryPool>      memory_pool;
    std::shared_ptr<TLBManager>      tlb_manager;

    const stream_t      NUM_STREAMS;
    const stream_mask_t MANAGED_STREAMS;
    const size_t        NUM_BUFFERS_TO_ENQUEUE;
    const size_t        BUFFER_CAPACITY;

    // State for each stream
    // There is one mutex to protect and changes in the stream_state.
    // This makes this implementation effectively single-threaded. However,
    // it seems very unlikely that it is required to e.g. read several stream outputs
    // simultaneously. This also means it's sufficient to hold a lock guard in the public functions.
    // No explicit locking in the private functions is needed!
    std::mutex                                             enqueued_buffers_mutex;
    std::vector<std::queue<std::shared_ptr<OutputHandle>>> enqueued_handles;
    std::vector<std::queue<Buffer>>                        enqueued_buffers;

    // Diagnostics only; guarded by enqueued_buffers_mutex like everything else.
    std::vector<size_t> stat_enqueued_total;
    std::vector<size_t> stat_interrupts;
    std::vector<size_t> stat_bytes_written;

    /**
     * Releases all memory in the given queue of buffers
     * @param queue
     */
    void free_buffers_in_queue(std::queue<Buffer> &queue);

    /**
     * For the given stream_id, takes the currently used buffer from the
     * FIFO of memory_in_use and places it into the memory that has been transferred.
     * Additionally, the memory is resized to fit the size actually used by the FPGA!
     * @param stream_id
     * @param bytes_written
     * @param last
     */
    void move_current_buffer_to_handle(stream_t stream_id, uint32_t bytes_written, bool last);

    /**
     * Allocates a new buffer for the given stream and sends it to the FPGA.
     * @param stream_id
     */
    void enqueue_buffer_for_stream(stream_t stream_id);

    /**
     * Allocates new buffers for the given stream until there are at least NUM_BUFFERS_TO_ENQUEUE.
     * @param stream_id
     */
    void ensure_stream_has_buffers(stream_t stream_id);

    /**
     * Write the CSR register for this stream's buffer vaddr
     */
    void write_vaddr_register(stream_t stream_id, size_t vaddr);

    /**
     * Write the CSR register for this stream's buffer size
     */
    void write_size_register(stream_t stream_id, size_t size);

    /**
     * Writes the CSR registers to add a new buffer to the FPGA for the given stream.
     * @param stream_id The stream this buffer is done for
     * @param buffer The buffer to write the registers for
     */
    void write_register_for_buffer(stream_t stream_id, Buffer &buffer);
};

} // namespace libstf
