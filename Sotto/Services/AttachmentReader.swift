import Foundation
import PDFKit
import UniformTypeIdentifiers

struct Attachment: Hashable, Sendable {
    var name: String
    var text: String
    var byteCount: Int
    var wasTruncated: Bool
}

enum AttachmentError: LocalizedError {
    case unsupportedType(String)
    case unreadable(String)
    case tooLarge(String, Int64)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            return "“\(name)” isn't a type Sotto can read. Attach text, Markdown, code, CSV, JSON, RTF or PDF."
        case .unreadable(let name):
            return "“\(name)” couldn't be read."
        case .tooLarge(let name, let size):
            return "“\(name)” is \(Format.bytes(size)); attachments are limited to \(Format.bytes(AttachmentReader.maximumFileBytes))."
        case .empty(let name):
            return "“\(name)” has no readable text."
        }
    }
}

/// Extracts plain text from dropped or picked files so it can be sent to a model.
enum AttachmentReader {
    static let maximumFileBytes: Int64 = 25_000_000
    static let maximumCharacters = 60_000
    static let supportedTypes: [UTType] = [.plainText, .utf8PlainText, .text, .sourceCode, .json, .commaSeparatedText, .rtf, .pdf, .xml, .yaml, .html, .log, .shellScript, .swiftSource, .pythonScript]

    static func read(_ url: URL) throws -> Attachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        if size > maximumFileBytes {
            throw AttachmentError.tooLarge(name, size)
        }

        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let raw: String
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: url) else { throw AttachmentError.unreadable(name) }
            raw = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        } else if type.conforms(to: .rtf) {
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
                throw AttachmentError.unreadable(name)
            }
            raw = attributed.string
        } else if type.conforms(to: .text) || supportedTypes.contains(where: { type.conforms(to: $0) }) || isProbablyText(url) {
            guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable(name) }
            guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw AttachmentError.unreadable(name)
            }
            raw = string
        } else {
            throw AttachmentError.unsupportedType(name)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AttachmentError.empty(name) }
        let truncated = trimmed.count > maximumCharacters
        let text = truncated ? String(trimmed.prefix(maximumCharacters)) + "\n\n[Attachment truncated at \(Format.integer(maximumCharacters)) characters]" : trimmed
        return Attachment(name: name, text: text, byteCount: Int(size), wasTruncated: truncated)
    }

    /// Sniffs the first kilobyte for control characters to accept code files with unknown extensions.
    private static func isProbablyText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1024), !head.isEmpty else { return false }
        let controlBytes = head.filter { $0 < 0x09 || ($0 > 0x0D && $0 < 0x20) }.count
        return Double(controlBytes) / Double(head.count) < 0.02
    }
}
