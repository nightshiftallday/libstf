#pragma once

#include <string>

namespace libstf {

/**
 * Severity of a log record. Ordered ascending; the global level filter drops records below the
 * configured threshold (see set_log_level).
 */
enum class LogLevel : unsigned char { TRACE, DEBUG, INFO, WARNING, ERROR, FATAL, OFF };

const char *to_string(LogLevel level);

/**
 * A pluggable destination for libstf (and anything built on it) log records. The default sink
 * writes to stderr. A host application can inject its own via set_log_sink(). Implementations must
 * be thread-safe.
 */
class LogSink {
  public:
    virtual ~LogSink()                                           = default;
    virtual void log(LogLevel level, const std::string &message) = 0;
};

/**
 * Installs the process-wide sink. Meant to be called once at startup, not swapped on the hot path.
 * The sink must outlive all subsequent log() calls; this call does not free the previous sink.
 * @param sink The sink to install, or nullptr to restore the default stderr sink.
 */
void set_log_sink(LogSink *sink);

/**
 * Sets the global severity threshold. Records below the threshold are dropped by log() before the
 * message is touched. Defaults to LogLevel::INFO; LogLevel::OFF silences all logging.
 * @param level The lowest severity that will be emitted.
 */
void set_log_level(LogLevel level);

/**
 * Whether a record at `level` would be emitted under the current threshold. A single relaxed atomic
 * load, cheap enough to gate any extra work a call site does before logging.
 * @param level The severity to test.
 * @return True if a record at this level passes the threshold.
 */
[[nodiscard]] bool should_log(LogLevel level);

/**
 * Emits a message verbatim at `level`.
 * @param level   The severity of the record.
 * @param message The message, taken as-is.
 */
void log(LogLevel level, const char *message);

/**
 * Emits a std::string verbatim at `level`.
 * @param level   The severity of the record.
 * @param message The message, taken as-is.
 */
void log(LogLevel level, const std::string &message);

/**
 * Formats and emits a record at `level`, printf-style. Formatting (via vsnprintf) happens only
 * after the level passes the threshold, so a filtered-out call never pays for it. The arguments
 * must be printf-compatible (scalars, pointers, C strings), exactly as for printf itself.
 * @param level The severity of the record.
 * @param fmt   A printf-style format string.
 */
template <typename... Args> void log(LogLevel level, const char *fmt, Args... args);

// Worker behind the variadic template. Defined in the .cpp so vsnprintf stays out of the header. It
// does the level check, the two-pass vsnprintf, and the sink dispatch. The format attribute lets
// the compiler check the specifiers against the (by-value, printf-compatible) arguments.
void log_formatted(LogLevel level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

template <typename... Args> void log(LogLevel level, const char *fmt, Args... args) {
    // Pass arguments by value so they undergo the default argument promotions a C variadic expects.
    // Callers supply printf-compatible types only (this is not a type-safe {} formatter).
    log_formatted(level, fmt, args...);
}

} // namespace libstf
