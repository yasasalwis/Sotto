import Foundation

/// Writes a minimal, valid GGUF v3 file with metadata only. Used to exercise the
/// header reader without shipping real weights in the repository.
enum SyntheticGGUF {
    enum Value {
        case uint32(UInt32)
        case string(String)
    }

    static func write(to url: URL, metadata: [(String, Value)]) throws {
        var data = Data()
        data.append(contentsOf: Array("GGUF".utf8))
        append(&data, UInt32(3))
        append(&data, UInt64(0)) // tensor count
        append(&data, UInt64(metadata.count))
        for (key, value) in metadata {
            appendString(&data, key)
            switch value {
            case .uint32(let number):
                append(&data, UInt32(4))
                append(&data, number)
            case .string(let text):
                append(&data, UInt32(8))
                appendString(&data, text)
            }
        }
        // Pad to the default 32-byte alignment expected before tensor data.
        while data.count % 32 != 0 {
            data.append(0)
        }
        try data.write(to: url)
    }

    private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func appendString(_ data: inout Data, _ text: String) {
        let bytes = Array(text.utf8)
        append(&data, UInt64(bytes.count))
        data.append(contentsOf: bytes)
    }
}
