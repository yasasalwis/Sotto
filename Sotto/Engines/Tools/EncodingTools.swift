import CryptoKit
import Foundation

/// The four remaining built-ins: encoding, hashing, random numbers and a token estimate.
enum EncodingTools {
    // MARK: - encode_text

    static let formats = ["base64", "hex", "url"]
    static let directions = ["encode", "decode"]

    static func encode(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let format = try ToolArguments.choice(arguments, "format", from: formats)
        let direction = try ToolArguments.choice(arguments, "direction", from: directions, fallback: "encode")
        let result = direction == "encode" ? try encode(text, as: format) : try decode(text, from: format)
        return "\(format) \(direction)d:\n\(result)"
    }

    static func encode(_ text: String, as format: String) throws -> String {
        let data = Data(text.utf8)
        switch format {
        case "base64": return data.base64EncodedString()
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        default:
            guard let escaped = text.addingPercentEncoding(withAllowedCharacters: .sottoURLValueAllowed) else {
                throw ToolExecutionError.invalidArguments("that text cannot be percent-encoded")
            }
            return escaped
        }
    }

    static func decode(_ text: String, from format: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case "base64":
            guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
                  let decoded = String(data: data, encoding: .utf8) else {
                throw ToolExecutionError.invalidArguments("that is not base64 holding readable text")
            }
            return decoded
        case "hex":
            let digits = trimmed.replacingOccurrences(of: " ", with: "")
            guard digits.count % 2 == 0, !digits.isEmpty else {
                throw ToolExecutionError.invalidArguments("hex needs an even number of digits")
            }
            var bytes: [UInt8] = []
            var index = digits.startIndex
            while index < digits.endIndex {
                let next = digits.index(index, offsetBy: 2)
                guard let byte = UInt8(digits[index..<next], radix: 16) else {
                    throw ToolExecutionError.invalidArguments("“\(digits[index..<next])” is not a hex byte")
                }
                bytes.append(byte)
                index = next
            }
            guard let decoded = String(bytes: bytes, encoding: .utf8) else {
                throw ToolExecutionError.invalidArguments("those bytes are not readable text")
            }
            return decoded
        default:
            guard let decoded = trimmed.removingPercentEncoding else {
                throw ToolExecutionError.invalidArguments("that is not percent-encoded text")
            }
            return decoded
        }
    }

    // MARK: - hash_text

    /// SHA-2 only. MD5 and SHA-1 are left out deliberately: they are broken for every purpose a
    /// user would reach for a hash, and offering them invites someone to use one.
    static let algorithms = ["sha256", "sha384", "sha512"]

    static func hash(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let algorithm = try ToolArguments.choice(arguments, "algorithm", from: algorithms, fallback: "sha256")
        let data = Data(text.utf8)
        let digest: String
        switch algorithm {
        case "sha384": digest = SHA384.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha512": digest = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default: digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return "\(algorithm) of \(data.count) byte\(data.count == 1 ? "" : "s"):\n\(digest)"
    }

    // MARK: - random_number

    static let maximumRandomCount = 20

    static func random(_ arguments: [String: Any]) throws -> String {
        let low = ToolArguments.integer(arguments, "minimum", fallback: 1, in: -1_000_000_000...1_000_000_000)
        let high = ToolArguments.integer(arguments, "maximum", fallback: 100, in: -1_000_000_000...1_000_000_000)
        guard low <= high else {
            throw ToolExecutionError.invalidArguments("“minimum” (\(low)) is above “maximum” (\(high))")
        }
        let count = ToolArguments.integer(arguments, "count", fallback: 1, in: 1...maximumRandomCount)
        var generator = SystemRandomNumberGenerator()
        let numbers = (0..<count).map { _ in Int.random(in: low...high, using: &generator) }
        let list = numbers.map(String.init).joined(separator: ", ")
        return count == 1
            ? "\(list) (random whole number from \(low) to \(high))"
            : "\(count) random whole numbers from \(low) to \(high): \(list)"
    }

    // MARK: - estimate_tokens

    static func estimateTokens(_ arguments: [String: Any]) throws -> String {
        let text = try ToolArguments.text(arguments, "text")
        let tokens = TokenEstimator.estimate(text)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return """
        about \(Format.integer(tokens)) tokens
        \(Format.integer(text.count)) characters, \(Format.integer(words)) words
        This is an estimate of roughly four characters per token, not a real tokenizer count.
        """
    }
}
