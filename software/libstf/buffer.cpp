#include <libstf/buffer.hpp>

namespace libstf {

BufferDeleter::BufferDeleter(std::shared_ptr<MemoryPool> memory_pool) : memory_pool(memory_pool) {}

void BufferDeleter::operator()(Buffer const *buffer) const {
    // First: free the allocation the struct manages
    memory_pool->free(buffer->ptr, buffer->capacity);
    // Then: free the struct itself!
    delete buffer;
}

std::shared_ptr<Buffer> make_buffer(std::shared_ptr<MemoryPool> memory_pool, void *ptr, size_t size,
                                    size_t capacity) {
    return std::shared_ptr<Buffer>(new Buffer{.ptr = ptr, .size = size, .capacity = capacity},
                                   BufferDeleter(memory_pool));
}

std::shared_ptr<Buffer> make_buffer(std::shared_ptr<MemoryPool> memory_pool, size_t size,
                                    Status &status) {
    void *ptr;
    status = memory_pool->allocate(size, &ptr);

    return std::shared_ptr<Buffer>(new Buffer{.ptr = ptr, .size = size, .capacity = size},
                                   BufferDeleter(memory_pool));
}

} // namespace libstf
