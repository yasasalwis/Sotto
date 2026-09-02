import Foundation

/// Accumulates raw token bytes and releases only complete UTF-8 scalars, so a
/// multi-byte character split across two tokens is never surfaced as garbage.
struct UTF8Assembler {
    private var buffer: [UInt8] = []

    var hasPendingBytes: Bool { !buffer.isEmpty }

    mutating func append(_ bytes: some Sequence<UInt8>) -> String? {
        buffer.append(contentsOf: bytes)
        return drainComplete()
    }

    /// Releases everything, replacing any invalid trailing bytes with U+FFFD.
    mutating func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let text = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        return text
    }

    private mutating func drainComplete() -> String? {
        guard !buffer.isEmpty else { return nil }
        var cut = buffer.count
        var index = buffer.count - 1
        var trailing = 0
        while index >= 0, trailing < 3, buffer[index] & 0xC0 == 0x80 {
            index -= 1
            trailing += 1
        }
        if index >= 0 {
            let lead = buffer[index]
            let expected: Int
            if lead >= 0xF0 {
                expected = 4
            } else if lead >= 0xE0 {
                expected = 3
            } else if lead >= 0xC0 {
                expected = 2
            } else {
                expected = 1
            }
            if lead >= 0xC0, trailing + 1 < expected {
                cut = index
            }
        }
        guard cut > 0 else { return nil }
        let complete = Array(buffer[0..<cut])
        buffer.removeFirst(cut)
        return String(decoding: complete, as: UTF8.self)
    }
}
