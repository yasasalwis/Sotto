import SwiftUI

/// A small block-level Markdown renderer: paragraphs, quotes, fenced code and lists.
/// Inline formatting inside blocks goes through `AttributedString(markdown:)`.
enum MarkdownBlock: Hashable, Identifiable {
    case paragraph(String)
    case quote([String])
    case code(language: String?, text: String)
    case bullets([String])
    case numbered([String])
    case heading(level: Int, text: String)

    var id: Int { hashValue }

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote)); quote = [] }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }
        func flushAll() {
            flushParagraph(); flushQuote(); flushLists()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
                    codeLines = []
                    codeLanguage = nil
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                    let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushAll()
                continue
            }
            if line.hasPrefix("#") {
                flushAll()
                let level = min(line.prefix(while: { $0 == "#" }).count, 4)
                let content = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: content))
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph(); flushLists()
                let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    quote.append("")
                } else if let last = quote.last, !last.isEmpty {
                    quote[quote.count - 1] = last + " " + content
                } else {
                    quote.append(content)
                }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushParagraph(); flushQuote()
                if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if let match = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flushParagraph(); flushQuote()
                if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
                numbered.append(String(match.2))
                continue
            }
            flushQuote(); flushLists()
            paragraph.append(line)
        }
        if inCode {
            blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
        }
        flushAll()
        return blocks.compactMap { block in
            if case .quote(let lines) = block {
                let cleaned = lines.filter { !$0.isEmpty }
                return cleaned.isEmpty ? nil : .quote(cleaned)
            }
            return block
        }
    }
}

struct MarkdownBlocksView: View {
    let text: String
    var fontSize: CGFloat = 15
    var lineSpacing: CGFloat = 5
    var color: Color = Theme.Colors.text
    var spacing: CGFloat = 14

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(blocks) { block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let content):
            inline(content)
        case .heading(let level, let content):
            Text(content)
                .font(Theme.Fonts.sans(fontSize + CGFloat(max(0, 4 - level)) * 1.5, weight: .medium))
                .foregroundStyle(Theme.Colors.ink)
        case .quote(let lines):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    inline(line, color: Theme.Colors.textSecondary)
                }
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.Colors.accentSoft).frame(width: 2)
            }
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language {
                    MonoText(language, size: 10, color: Theme.Colors.faint)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(Theme.Fonts.mono(fontSize - 2))
                        .foregroundStyle(Theme.Colors.ink)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(Theme.Fonts.sans(fontSize)).foregroundStyle(Theme.Colors.hint)
                        inline(item)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        MonoText("\(index + 1).", size: fontSize - 2, color: Theme.Colors.hint)
                        inline(item)
                    }
                }
            }
        }
    }

    private func inline(_ content: String, color: Color? = nil) -> some View {
        let attributed = (try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content)
        return Text(attributed)
            .font(Theme.Fonts.sans(fontSize))
            .lineSpacing(lineSpacing)
            .foregroundStyle(color ?? self.color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
