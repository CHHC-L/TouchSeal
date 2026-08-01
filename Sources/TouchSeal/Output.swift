import Darwin
import Foundation

/// Keeps secret bytes (stdout) and human-facing text (stderr) strictly apart.
protocol OutputWriter {
    /// Writes raw bytes to stdout with no framing, prefix, or trailing newline.
    func writeStandardOutput(_ data: Data) throws
    /// Writes a diagnostic line to stderr. Never called with secret material.
    func writeStandardError(_ text: String)
}

struct StandardOutputWriter: OutputWriter {
    func writeStandardOutput(_ data: Data) throws {
        try Self.writeAll(data, to: STDOUT_FILENO)
    }

    func writeStandardError(_ text: String) {
        var line = text
        if !line.hasSuffix("\n") { line.append("\n") }
        try? Self.writeAll(Data(line.utf8), to: STDERR_FILENO)
    }

    /// Writes every byte, retrying short writes and `EINTR`.
    ///
    /// Uses `write(2)` directly rather than `FileHandle` so the secret is
    /// handed to the kernel straight from its `Data` buffer.
    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw TouchSealError.general("Unable to write output: \(String(cString: strerror(errno)))")
                }
                if written == 0 { break }
                offset += written
            }
        }
    }
}
