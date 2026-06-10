#include "libstf/logging.hpp"

#include <atomic>
#include <cstdarg>
#include <cstdio>

namespace libstf {

const char *to_string(LogLevel level) {
    switch (level) {
    case LogLevel::TRACE:
        return "TRACE";
    case LogLevel::DEBUG:
        return "DEBUG";
    case LogLevel::INFO:
        return "INFO";
    case LogLevel::WARNING:
        return "WARNING";
    case LogLevel::ERROR:
        return "ERROR";
    case LogLevel::FATAL:
        return "FATAL";
    case LogLevel::OFF:
        return "OFF";
    }
    return "?";
}

namespace {

// Default sink. Records from different threads must not interleave, so we assemble the whole line
// into one buffer and emit it with a single fwrite. A lone fwrite is serialized by the C runtime's
// per-stream lock, so the record stays intact without an explicit mutex of our own.
class StderrLogSink : public LogSink {
  public:
    void log(LogLevel level, const std::string &message) override {
        std::string line = "[libstf] [";
        line += to_string(level);
        line += "] ";
        line += message;
        line += '\n';
        std::fwrite(line.data(), 1, line.size(), stderr);
    }
};

LogSink &default_sink() {
    static StderrLogSink sink;
    return sink;
}

std::atomic<LogSink *> g_sink{&default_sink()};
std::atomic<LogLevel>  g_level{LogLevel::INFO};

} // namespace

void set_log_sink(LogSink *sink) {
    g_sink.store(sink ? sink : &default_sink(), std::memory_order_relaxed);
}

void set_log_level(LogLevel level) { g_level.store(level, std::memory_order_relaxed); }

bool should_log(LogLevel level) { return level >= g_level.load(std::memory_order_relaxed); }

void log(LogLevel level, const char *message) {
    if (!should_log(level)) {
        return;
    }
    g_sink.load(std::memory_order_relaxed)->log(level, message);
}

void log(LogLevel level, const std::string &message) {
    if (!should_log(level)) {
        return;
    }
    g_sink.load(std::memory_order_relaxed)->log(level, message);
}

void log_formatted(LogLevel level, const char *fmt, ...) {
    if (!should_log(level)) {
        return; // Skip formatting entirely for filtered-out records.
    }

    // First pass: measure the formatted length (vsnprintf returns the length it *would* have
    // written, excluding the null terminator). A fresh va_list is needed per pass.
    va_list args;
    va_start(args, fmt);
    const int needed = std::vsnprintf(nullptr, 0, fmt, args);
    va_end(args);

    if (needed < 0) {
        return; // Encoding error in the format string. Nothing safe to emit.
    }

    // Second pass: format into a buffer sized to fit (+1 for the null terminator vsnprintf writes).
    std::string message(static_cast<size_t>(needed), '\0');
    va_start(args, fmt);
    std::vsnprintf(message.data(), message.size() + 1, fmt, args);
    va_end(args);

    g_sink.load(std::memory_order_relaxed)->log(level, message);
}

} // namespace libstf
