import Foundation

enum ModelNaming {
    /// Compresses a model name into the sidebar label style: "Qwen2.5 7B Instruct" → "qwen2.5-7b".
    static func shortLabel(for name: String) -> String {
        let dropped: Set<String> = ["instruct", "chat", "it", "v0.1", "v0.2", "v0.3", "gguf", "base", "model"]
        let parts = name
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init)
            .filter { !dropped.contains($0) }
        let label = parts.prefix(3).joined(separator: "-")
        return label.isEmpty ? name.lowercased() : label
    }

    /// Strips a `.gguf` extension and quantisation suffix to produce a display name.
    static func displayName(fromFileName fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension
        let quantPattern = #"[-._](I?Q\d[_A-Z0-9]*|F16|F32|BF16)$"#
        if let regex = try? NSRegularExpression(pattern: quantPattern, options: .caseInsensitive) {
            base = regex.stringByReplacingMatches(in: base, range: NSRange(base.startIndex..., in: base), withTemplate: "")
        }
        return base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    /// The label the design shows under the Apple model.
    static let appleShortLabel = "apple · on-device"
}
