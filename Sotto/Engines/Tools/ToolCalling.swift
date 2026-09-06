import Foundation

/// Prompt-based tool calling, used for models without native tool support (GGUF via llama.cpp).
/// The model is asked to answer with a `<tool_call>` block, which the scanner below lifts out of
/// the token stream before any of it reaches the transcript.
enum ToolPromptFormatter {
    static let openTag = "<tool_call>"
    static let closeTag = "</tool_call>"
    /// The Markdown-fence spelling of `openTag`, which models without a `<tool_call>` token in
    /// their vocabulary write instead. Recognised on the way in, never produced by Sotto.
    static let fencedOpenTag = "```tool_call"
    static let fence = "```"
    static let responseOpenTag = "<tool_response>"
    static let responseCloseTag = "</tool_response>"

    /// Shared restraint rule. Small models will call a tool for a greeting unless told plainly
    /// not to, so both engines put this in front of the tool list.
    static let usageRule = "Most messages need no tool. Answer from your own knowledge unless the request plainly asks for something you cannot know or work out yourself. A greeting is never a reason to call a tool. Phrases such as \"in one word\", \"briefly\" or \"in short\" describe how to answer; they are not requests to count, measure, or look anything up. Never call a tool to decorate an answer with facts the user did not ask for. When a tool is genuinely needed, call one, use exactly what it returns, and never invent a result."

    static func instructions(for tools: [ToolSpec]) -> String {
        guard !tools.isEmpty else { return "" }
        var text = "# Tools\n\n\(usageRule)\n\nTo call a tool, reply with exactly this block and nothing else:\n"
        text += "\(openTag)\n{\"name\": \"<tool name>\", \"arguments\": {<arguments as JSON>}}\n\(closeTag)\n"
        text += "The result comes back inside \(responseOpenTag) tags; continue your answer from there.\n\nAvailable tools:\n"
        for tool in tools {
            text += "- \(tool.name): \(tool.description)\n  parameters: \(tool.parametersSchemaJSON)\n"
        }
        return text
    }

    static func systemPrompt(base: String?, tools: [ToolSpec]) -> String? {
        let extra = instructions(for: tools)
        guard !extra.isEmpty else { return base }
        let trimmed = base?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "You are a helpful assistant.\n\n" + extra : trimmed + "\n\n" + extra
    }

    static func callBlock(_ call: ToolCallRequest) -> String {
        let arguments = call.argumentsJSON.isEmpty ? "{}" : call.argumentsJSON
        return "\(openTag)\n{\"name\": \"\(call.name)\", \"arguments\": \(arguments)}\n\(closeTag)"
    }

    static func responseBlock(_ result: ToolRunResult) -> String {
        "\(responseOpenTag)\n\(result.text)\n\(responseCloseTag)"
    }
}

enum ToolCallParser {
    /// Reads the JSON inside a tool-call block, tolerating code fences and a `parameters` alias.
    /// Small models sometimes omit the name; when `tools` is supplied and exactly one of them fits
    /// the argument keys, that tool is used rather than losing the call.
    static func parse(_ block: String, tools: [ToolSpec] = []) -> ToolCallRequest? {
        var inner = block
        if let open = inner.range(of: ToolPromptFormatter.openTag) { inner = String(inner[open.upperBound...]) }
        if let close = inner.range(of: ToolPromptFormatter.closeTag) { inner = String(inner[..<close.lowerBound]) }
        inner = inner.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let start = inner.firstIndex(of: "{"), let end = inner.lastIndex(of: "}"), start < end else { return nil }
        let json = String(inner[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let arguments = object["arguments"] ?? object["parameters"] ?? [String: Any]()
        if let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return ToolCallRequest(name: name, argumentsJSON: normalize(arguments))
        }
        guard let inferred = inferName(arguments: arguments, tools: tools) else { return nil }
        return ToolCallRequest(name: inferred, argumentsJSON: normalize(arguments))
    }

    /// The single tool whose parameters match these argument keys, if there is exactly one.
    static func inferName(arguments: Any, tools: [ToolSpec]) -> String? {
        guard !tools.isEmpty, let object = arguments as? [String: Any], !object.isEmpty else { return nil }
        let keys = Set(object.keys)
        let candidates = tools.filter { spec in
            let declared = Set(spec.parameters.map(\.name))
            let required = Set(spec.parameters.filter(\.isRequired).map(\.name))
            return keys.isSubset(of: declared) && required.isSubset(of: keys)
        }
        return candidates.count == 1 ? candidates[0].name : nil
    }

    static func normalize(_ arguments: Any) -> String {
        if let object = arguments as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            return String(decoding: encoded, as: UTF8.self)
        }
        if let text = arguments as? String, let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            return String(decoding: encoded, as: UTF8.self)
        }
        return "{}"
    }
}

/// Splits a streamed reply into visible text and tool calls, holding back partial tags so a
/// half-written `<tool_call>` never flashes in the UI.
///
/// Two shapes are recognised. Models that write the tags as plain text produce a tagged block.
/// Models whose vocabulary holds `<tool_call>` as a special token (Qwen, among others) have those
/// tokens stripped before the text reaches us, so a reply that is nothing but a JSON object with a
/// `name` and `arguments` is treated as a call too.
///
/// `<tool_response>` is stripped as well. The system prompt tells the model its results arrive
/// inside those tags and `GGUFEngine` feeds them back that way, so a small model readily writes
/// the wrapper itself — sometimes replaying a whole exchange it invented. Nothing inside it is
/// worth showing: a genuine result is already rendered as a tool card above the answer, and an
/// invented one is a hallucination wearing a protocol tag. Left unhandled it reached the
/// transcript verbatim, which is how `<tool_response>date</tool_response>` turned up in a chat.
struct ToolCallScanner {
    private let tools: [ToolSpec]

    init(tools: [ToolSpec] = []) {
        self.tools = tools
    }

    private enum Mode {
        case text
        case tagged
        case bareJSON
        /// Inside a `<tool_response>` the model wrote itself; everything up to the closing tag
        /// is dropped.
        case responseEcho
    }

    /// A protocol tag found in text mode, and where it sits.
    private enum Marker {
        case call
        /// ```` ```tool_call ```` — the same call written as a Markdown fence.
        ///
        /// The prompt asks for a `<tool_call>` block, and a model that has no such token in its
        /// vocabulary reaches for the nearest thing it does know: a fenced code block with
        /// `tool_call` as the language. Gemma 2 2B did exactly that on an iPhone, and because
        /// nothing recognised the fence the whole call — JSON, closing tag and all — was rendered
        /// as a code block and no tool ever ran. From the outside that is an answer that never
        /// arrived.
        case callFence
        /// A closing call tag with no opener, left over when the opener was a stripped special
        /// token and the JSON was recovered on its own.
        case callClose
        case responseOpen
        /// A closing response tag with no opener — dropped on its own so it cannot dangle.
        case responseClose

        var tag: String {
            switch self {
            case .call: return ToolPromptFormatter.openTag
            case .callFence: return ToolPromptFormatter.fencedOpenTag
            case .callClose: return ToolPromptFormatter.closeTag
            case .responseOpen: return ToolPromptFormatter.responseOpenTag
            case .responseClose: return ToolPromptFormatter.responseCloseTag
            }
        }

        static let all: [Marker] = [.call, .callFence, .callClose, .responseOpen, .responseClose]
    }

    private var pending = ""
    private var block = ""
    private var mode = Mode.text
    /// What ends the block currently being collected. A tagged call ends at `</tool_call>`; a
    /// fenced one ends at either that or the closing fence, whichever the model wrote.
    private var closers: [String] = [ToolPromptFormatter.closeTag]
    private var emittedVisibleText = false
    private var json = JSONObjectScanner()

    struct Output {
        var visible: String = ""
        var call: ToolCallRequest?
        /// Set when a block closed but could not be parsed, so the caller can surface it.
        var unparsedBlock: String?
    }

    var isInsideCall: Bool { mode != .text }

    mutating func feed(_ delta: String) -> Output {
        pending += delta
        var output = Output()
        while true {
            switch mode {
            case .tagged:
                if let close = Self.firstRange(of: closers, in: pending) {
                    block += String(pending[..<close.upperBound])
                    pending = String(pending[close.upperBound...])
                    mode = .text
                    let finished = block
                    block = ""
                    if let call = ToolCallParser.parse(finished, tools: tools) {
                        output.call = call
                    } else {
                        output.unparsedBlock = finished
                    }
                    return output
                }
                let keep = closers.map { Self.partialSuffixLength(of: pending, matching: $0) }.max() ?? 0
                let cut = pending.index(pending.endIndex, offsetBy: -keep)
                block += String(pending[..<cut])
                pending = String(pending[cut...])
                return output

            case .bareJSON:
                let consumed = json.consume(pending)
                block += String(pending[..<consumed.endIndex])
                pending = String(pending[consumed.endIndex...])
                guard consumed.isComplete else { return output }
                mode = .text
                let finished = block
                block = ""
                json = JSONObjectScanner()
                if let call = ToolCallParser.parse(finished, tools: tools) {
                    output.call = call
                } else {
                    // Not a call after all: it was just JSON in the answer.
                    output.visible += finished
                    emittedVisibleText = true
                }
                continue

            case .responseEcho:
                if let close = pending.range(of: ToolPromptFormatter.responseCloseTag) {
                    pending = String(pending[close.upperBound...])
                    mode = .text
                    continue
                }
                // Hold back only what could still become the closing tag; drop the rest.
                let keptTail = Self.partialSuffixLength(of: pending, matching: ToolPromptFormatter.responseCloseTag)
                pending = String(pending.suffix(keptTail))
                return output

            case .text:
                if let marker = Self.firstMarker(in: pending) {
                    let leading = String(pending[..<marker.range.lowerBound])
                    output.visible += leading
                    if !leading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { emittedVisibleText = true }
                    pending = String(pending[marker.range.upperBound...])
                    switch marker.kind {
                    case .call:
                        block = ToolPromptFormatter.openTag
                        closers = [ToolPromptFormatter.closeTag]
                        mode = .tagged
                    case .callFence:
                        // Normalised to the tag the parser expects. A fenced call may be closed
                        // either way — `</tool_call>` because the prompt asked for it, or the
                        // fence because that is how the model opened it — so accept both.
                        block = ToolPromptFormatter.openTag
                        closers = [ToolPromptFormatter.closeTag, ToolPromptFormatter.fence]
                        mode = .tagged
                    case .callClose, .responseClose:
                        break
                    case .responseOpen:
                        mode = .responseEcho
                    }
                    continue
                }
                // A reply that opens with a JSON object may be a call whose tags were stripped.
                if !emittedVisibleText, let brace = pending.firstIndex(of: "{"),
                   pending[..<brace].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.visible += String(pending[..<brace])
                    pending = String(pending[brace...])
                    block = ""
                    json = JSONObjectScanner()
                    mode = .bareJSON
                    continue
                }
                let keep = Self.heldBackSuffixLength(of: pending)
                let cut = pending.index(pending.endIndex, offsetBy: -keep)
                let ready = String(pending[..<cut])
                output.visible += ready
                if !ready.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { emittedVisibleText = true }
                pending = String(pending[cut...])
                return output
            }
        }
    }

    /// Releases held-back text at end of stream. An unterminated call still counts if it parses.
    mutating func flush() -> Output {
        var output = Output()
        switch mode {
        case .tagged:
            output.call = ToolCallParser.parse(block + pending + ToolPromptFormatter.closeTag, tools: tools)
            if output.call == nil { output.visible = block + pending }
        case .bareJSON:
            let text = block + pending
            if let call = ToolCallParser.parse(text, tools: tools) {
                output.call = call
            } else {
                output.visible = text
            }
        case .responseEcho:
            // An unterminated echo is still an echo: dropping it beats ending a reply on a
            // half-written protocol tag.
            break
        case .text:
            output.visible = pending
        }
        pending = ""
        block = ""
        json = JSONObjectScanner()
        mode = .text
        return output
    }

    /// Removes `<tool_response>` blocks from a finished or cumulative string.
    ///
    /// The streaming path above is for engines that hand over one delta at a time. Apple's
    /// `LanguageModelSession` instead yields a growing snapshot of the whole answer, so it needs
    /// a plain function over that snapshot. It calls tools natively and is never shown these
    /// tags, but a 3B model can still write the convention it met in pretraining, and nothing
    /// between the session and the transcript was looking.
    ///
    /// An unterminated block drops everything after it: mid-stream that text is the inside of the
    /// echo, and the snapshot that completes the tag replaces this one anyway.
    static func strippingEchoedResponses(_ text: String) -> String {
        guard text.contains(ToolPromptFormatter.responseOpenTag) || text.contains(ToolPromptFormatter.responseCloseTag) else {
            return text
        }
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: ToolPromptFormatter.responseOpenTag) {
            result += rest[..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: ToolPromptFormatter.responseCloseTag) else { return result }
            rest = after[close.upperBound...]
        }
        result += rest
        return result.replacingOccurrences(of: ToolPromptFormatter.responseCloseTag, with: "")
    }

    /// The first protocol tag in `text`, if any — earliest position wins, so a `<tool_response>`
    /// that opens before a stray `</tool_response>` is treated as a block rather than a stray.
    ///
    /// Ties go to the longest tag, which is what keeps ```` ```tool_call ```` from being read as a
    /// bare fence and `<tool_call>` from being read as a stray closer.
    private static func firstMarker(in text: String) -> (kind: Marker, range: Range<String.Index>)? {
        Marker.all
            .compactMap { marker in text.range(of: marker.tag).map { (kind: marker, range: $0) } }
            .min {
                $0.range.lowerBound == $1.range.lowerBound
                    ? $0.kind.tag.count > $1.kind.tag.count
                    : $0.range.lowerBound < $1.range.lowerBound
            }
    }

    /// The earliest occurrence of any of `tags` in `text`.
    private static func firstRange(of tags: [String], in text: String) -> Range<String.Index>? {
        tags.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
    }

    /// How much of the tail to keep unpublished because it could still grow into any protocol
    /// tag. `<tool_` is the shared prefix of a call and a response, so holding back only what
    /// `<tool_call>` needs would let `<tool_response>` slip out one character at a time.
    static func heldBackSuffixLength(of text: String) -> Int {
        Marker.all.map { partialSuffixLength(of: text, matching: $0.tag) }.max() ?? 0
    }

    /// Length of the longest suffix of `text` that is also a proper prefix of `tag`.
    static func partialSuffixLength(of text: String, matching tag: String) -> Int {
        let maxLength = min(text.count, tag.count - 1)
        guard maxLength > 0 else { return 0 }
        for length in stride(from: maxLength, through: 1, by: -1) where text.hasSuffix(String(tag.prefix(length))) {
            return length
        }
        return 0
    }
}

/// Tracks brace depth across chunks so a JSON object can be recognised as it streams in,
/// ignoring braces that appear inside string literals.
struct JSONObjectScanner {
    private var depth = 0
    private var inString = false
    private var escaped = false
    private var started = false

    struct Consumed {
        var endIndex: String.Index
        var isComplete: Bool
    }

    /// Consumes as much of `text` as belongs to the object, reporting where it stopped.
    mutating func consume(_ text: String) -> Consumed {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if escaped {
                escaped = false
                continue
            }
            if inString {
                if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{":
                depth += 1
                started = true
            case "}":
                depth -= 1
                if started, depth <= 0 {
                    return Consumed(endIndex: index, isComplete: true)
                }
            default:
                break
            }
        }
        return Consumed(endIndex: index, isComplete: false)
    }
}
