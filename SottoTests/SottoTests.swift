import Foundation
import Testing
@testable import Sotto

@MainActor
struct ModelRefTests {
    @Test func roundTripsRawValues() {
        let id = UUID()
        #expect(ModelRef(rawValue: "apple") == .apple)
        #expect(ModelRef(rawValue: ModelRef.gguf(id).rawValue) == .gguf(id))
        #expect(ModelRef(rawValue: "gguf:not-a-uuid") == nil)
        #expect(ModelRef(rawValue: "cloud") == nil)
        #expect(ModelRef.apple.isApple)
        #expect(ModelRef.gguf(id).ggufID == id)
    }
}

@MainActor
struct ModelNamingTests {
    @Test func shortLabelsMatchDesign() {
        #expect(ModelNaming.shortLabel(for: "Qwen2.5 7B Instruct") == "qwen2.5-7b")
        #expect(ModelNaming.shortLabel(for: "Llama 3.2 3B Instruct") == "llama-3.2-3b")
        #expect(ModelNaming.shortLabel(for: "Mistral 7B Instruct v0.3") == "mistral-7b")
        #expect(ModelNaming.shortLabel(for: "gemma-2-2b-it") == "gemma-2-2b")
    }

    @Test func displayNameStripsQuantSuffix() {
        #expect(ModelNaming.displayName(fromFileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf") == "Qwen2.5 3B Instruct")
        #expect(ModelNaming.displayName(fromFileName: "model.F16.gguf") == "model")
    }
}

@MainActor
struct FormatTests {
    @Test func bytesUseDecimalUnits() {
        #expect(Format.bytes(Int64(4_683_074_240)) == "4.7 GB")
        #expect(Format.bytes(Int64(911_503_488)) == "912 MB")
        #expect(Format.bytes(Int64(0)) == "0 B")
        #expect(Format.bytes(Int64(2_300)) == "2 KB")
    }

    @Test func tokensPerSecond() {
        #expect(Format.tokensPerSecond(41.23) == "41.2 tok/s")
        #expect(Format.tokensPerSecond(58, approximate: true, fractionDigits: 0) == "~58 tok/s")
        #expect(Format.tokensPerSecond(0) == "—")
    }

    @Test func secondsAndRemaining() {
        #expect(Format.seconds(1.94) == "1.9s")
        #expect(Format.seconds(12.4) == "12s")
        #expect(Format.remaining(seconds: 125) == "2 min left")
        #expect(Format.remaining(seconds: 30) == "30 s left")
    }

    @Test func contextLengths() {
        #expect(Format.contextLength(8192) == "8K")
        #expect(Format.contextLength(131072) == "128K")
        #expect(Format.contextLength(4096) == "4K")
        #expect(Format.contextLength(0) == "—")
    }

    @Test func integersAreGrouped() {
        #expect(Format.integer(2480).replacingOccurrences(of: "\u{202F}", with: ",").replacingOccurrences(of: ".", with: ",") == "2,480")
    }
}

@MainActor
struct ConversationGroupTests {
    @Test func bucketsByRecency() {
        let calendar = Calendar.current
        let now = Date()
        #expect(ConversationGroup.group(for: now, relativeTo: now, calendar: calendar) == .today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(ConversationGroup.group(for: yesterday, relativeTo: now, calendar: calendar) == .yesterday)
        let threeDays = calendar.date(byAdding: .day, value: -3, to: now)!
        #expect(ConversationGroup.group(for: threeDays, relativeTo: now, calendar: calendar) == .previousWeek)
        let month = calendar.date(byAdding: .day, value: -40, to: now)!
        #expect(ConversationGroup.group(for: month, relativeTo: now, calendar: calendar) == .earlier)
    }
}

@MainActor
struct TokenEstimatorTests {
    @Test func estimates() {
        #expect(TokenEstimator.estimate("") == 0)
        #expect(TokenEstimator.estimate("hello") == 2)
        #expect(TokenEstimator.estimate("a b c d e f") == 6)
    }
}

@MainActor
struct SamplingSettingsTests {
    @Test func overridesWinOverPersona() {
        let persona = Persona(name: "Editor", summary: "", systemPrompt: "", temperature: 0.4, topP: 0.8, maxTokens: 512)
        let conversation = Conversation(modelRef: .apple)
        conversation.temperatureOverride = 1.1
        let resolved = SamplingSettings.resolve(persona: persona, conversation: conversation)
        #expect(resolved.temperature == 1.1)
        #expect(resolved.topP == 0.8)
        #expect(resolved.maxTokens == 512)
    }

    @Test func clampsOutOfRangeValues() {
        let conversation = Conversation(modelRef: .apple)
        conversation.temperatureOverride = 9
        conversation.maxTokensOverride = 1
        let resolved = SamplingSettings.resolve(persona: nil, conversation: conversation)
        #expect(resolved.temperature == Persona.temperatureRange.upperBound)
        #expect(resolved.maxTokens == Persona.maxTokensRange.lowerBound)
    }
}

@MainActor
struct CatalogTests {
    @Test func bundledCatalogDecodes() throws {
        let catalog = try ModelCatalog.loadBundled()
        #expect(catalog.entries.count >= 8)
        for entry in catalog.entries {
            #expect(entry.url.scheme == "https")
            #expect(entry.url.host == "huggingface.co")
            #expect(entry.fileName.hasSuffix(".gguf"))
            #expect(entry.sizeBytes > 100_000_000)
            #expect(entry.estimatedMemoryBytes > entry.sizeBytes)
        }
        #expect(Set(catalog.entries.map(\.id)).count == catalog.entries.count)
    }

    /// The host pin is enforced when a catalog is decoded, not only asserted about the bundled
    /// file, so a tampered or future remote catalog cannot redirect a download elsewhere.
    @Test func decodingRejectsAnEntryThatLeavesThePinnedHost() throws {
        func catalogJSON(url: String) -> Data {
            Data("""
            {"version":1,"updatedAt":"2026-09-03","entries":[{
              "id":"x","name":"X","family":"X","publisher":"X","repository":"a/b",
              "fileName":"x.gguf","url":"\(url)","sizeBytes":200000000,"quantization":"Q4_K_M",
              "parameterLabel":"1B","contextLength":4096,"license":"MIT","summary":"x"}]}
            """.utf8)
        }

        #expect(throws: Never.self) {
            try ModelCatalog.decode(catalogJSON(url: "https://huggingface.co/a/b/resolve/main/x.gguf"))
        }
        #expect(throws: CatalogError.self) {
            try ModelCatalog.decode(catalogJSON(url: "https://evil.example.com/x.gguf"))
        }
        #expect(throws: CatalogError.self) {
            try ModelCatalog.decode(catalogJSON(url: "http://huggingface.co/a/b/resolve/main/x.gguf"))
        }
        // A lookalike host must not pass the suffix check.
        #expect(throws: CatalogError.self) {
            try ModelCatalog.decode(catalogJSON(url: "https://nothuggingface.co/x.gguf"))
        }
    }
}

@MainActor
struct MarkdownBlockTests {
    @Test func parsesQuotesParagraphsAndCode() {
        let text = """
        Here it is:

        > Welcome to Sotto.
        > Everything stays here.

        - one
        - two

        ```sh
        ls -la
        ```
        Done.
        """
        let blocks = MarkdownBlock.parse(text)
        #expect(blocks.count == 5)
        #expect(blocks[0] == .paragraph("Here it is:"))
        #expect(blocks[1] == .quote(["Welcome to Sotto. Everything stays here."]))
        #expect(blocks[2] == .bullets(["one", "two"]))
        #expect(blocks[3] == .code(language: "sh", text: "ls -la"))
        #expect(blocks[4] == .paragraph("Done."))
    }

    @Test func numberedListsAndHeadings() {
        let blocks = MarkdownBlock.parse("## Title\n1. first\n2. second")
        #expect(blocks == [.heading(level: 2, text: "Title"), .numbered(["first", "second"])])
    }

    @Test func unterminatedCodeStillRenders() {
        let blocks = MarkdownBlock.parse("```\nlet x = 1")
        #expect(blocks == [.code(language: nil, text: "let x = 1")])
    }
}

@MainActor
struct PromptBuilderTests {
    private func turns(_ count: Int) -> [ChatTurn] {
        (0..<count).map { index in
            ChatTurn(role: index % 2 == 0 ? .user : .assistant, content: String(repeating: "word ", count: 50))
        } + [ChatTurn(role: .user, content: "final question")]
    }

    @Test func dropsOldestTurnsToFit() async throws {
        let result = try await PromptBuilder.build(turns: turns(10), systemPrompt: "Be brief.", sampling: .default, contextLength: 512) { text in
            TokenEstimator.estimate(text)
        }
        #expect(result.droppedTurns > 0)
        #expect(result.request.turns.last?.content == "final question")
        #expect(result.request.turns.first?.role == .user || result.request.turns.first?.role == .assistant)
        #expect(result.estimatedPromptTokens <= 512)
    }

    @Test func keepsEverythingWhenItFits() async throws {
        let result = try await PromptBuilder.build(turns: turns(2), systemPrompt: nil, sampling: .default, contextLength: 8192) { TokenEstimator.estimate($0) }
        #expect(result.droppedTurns == 0)
        #expect(result.request.turns.count == 3)
    }

    @Test func rejectsPromptThatCannotFit() async {
        let huge = [ChatTurn(role: .user, content: String(repeating: "x ", count: 5000))]
        await #expect(throws: EngineError.self) {
            try await PromptBuilder.build(turns: huge, systemPrompt: nil, sampling: .default, contextLength: 512) { TokenEstimator.estimate($0) }
        }
    }

    @Test func requiresTrailingUserTurn() async {
        await #expect(throws: EngineError.noUserMessage) {
            try await PromptBuilder.build(turns: [ChatTurn(role: .assistant, content: "hi")], systemPrompt: nil, sampling: .default, contextLength: 4096) { TokenEstimator.estimate($0) }
        }
    }

    @Test func mergesConsecutiveUserMessagesAndSkipsFailures() {
        let conversation = Conversation(modelRef: .apple)
        let first = Message(role: .user, text: "one", createdAt: Date(timeIntervalSince1970: 1))
        let failed = Message(role: .assistant, text: "", createdAt: Date(timeIntervalSince1970: 2), state: .failed)
        let second = Message(role: .user, text: "two", createdAt: Date(timeIntervalSince1970: 3))
        conversation.messages = [first, failed, second]
        let turns = PromptBuilder.turns(from: conversation.orderedMessages)
        #expect(turns.count == 1)
        #expect(turns[0].content == "one\n\ntwo")
    }
}

@MainActor
struct ChatSessionTitleTests {
    @Test func titlesAreTrimmedToFirstLine() {
        #expect(ChatSession.title(from: "Rewrite the onboarding email.\nIt's too long.") == "Rewrite the onboarding email")
        #expect(ChatSession.title(from: "   ") == "New chat")
        let long = ChatSession.title(from: "Explain what a Kalman filter does to someone who knows algebra but not calculus")
        #expect(long.hasSuffix("…"))
        #expect(long.count <= 43)
    }
}

@MainActor
struct SettingsStoreTests {
    @Test func defaultsArePrivacyPreserving() {
        let suite = UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        #expect(store.crashReports == false)
        #expect(store.catalogUpdates == false)
        #expect(store.storeConversations == true)
        #expect(store.wifiOnlyDownloads == true)
        #expect(store.toolsEnabled == true)
        #expect(store.bytesSentThisMonth == 0)
    }

    @Test func launchArgumentStringsAreReadAsFlags() {
        let suite = UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!
        // The argument domain hands over strings, which a plain `as? Bool` cast would miss.
        suite.set("NO", forKey: SettingsStore.Key.storeConversations.rawValue)
        suite.set("YES", forKey: SettingsStore.Key.requireAppLock.rawValue)
        let store = SettingsStore(defaults: suite)
        #expect(store.storeConversations == false)
        #expect(store.requireAppLock == true)
        #expect(SettingsStore.bool(suite, .crashReports, default: true) == true)
    }

    @Test func byteAccountingRollsOverMonthly() {
        let suite = UserDefaults(suiteName: "SottoTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        store.recordBytesSent(1_000)
        #expect(store.bytesSentThisMonth == 1_000)
        #expect(store.bytesSentTotal == 1_000)
        store.bytesSentMonthKey = "1999-1"
        store.rolloverMonthIfNeeded()
        #expect(store.bytesSentThisMonth == 0)
        #expect(store.bytesSentTotal == 1_000)
        let reloaded = SettingsStore(defaults: suite)
        #expect(reloaded.bytesSentTotal == 1_000)
    }
}

@MainActor
struct ExportTests {
    @Test func exportsConversationsAsJSONAndMarkdown() throws {
        let conversation = Conversation(modelRef: .apple)
        conversation.title = "Regex help"
        conversation.messages = [Message(role: .user, text: "hi"), Message(role: .assistant, text: "hello", createdAt: Date().addingTimeInterval(1))]
        let export = ConversationExport.make(from: [conversation])
        let data = try export.jsonData()
        let decoded = try JSONDecoder.iso.decode(ConversationExport.self, from: data)
        #expect(decoded.conversations.first?.messages.count == 2)
        #expect(export.markdown().contains("## Regex help"))
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
struct AppleTranscriptTests {
    @Test func buildsAlternatingTranscript() {
        let turns: [ChatTurn] = [
            ChatTurn(role: .user, content: "a"),
            ChatTurn(role: .assistant, content: "b"),
            ChatTurn(role: .user, content: "dangling"),
        ]
        let transcript = AppleIntelligenceEngine.transcript(systemPrompt: "sys", history: turns[...])
        // instructions + prompt + response; the dangling prompt is dropped
        #expect(transcript.count == 3)
    }
}

@MainActor
struct ModelStoreTests {
    @Test func rejectsFilesWithoutMagic() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("nope".utf8).write(to: url)
        #expect(try ModelStore.hasGGUFMagic(url) == false)
        try Data("GGUF".utf8).write(to: url)
        #expect(try ModelStore.hasGGUFMagic(url) == true)
    }

    @Test func uniqueFileNamesAvoidCollisions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-store-\(UUID().uuidString)")
        let store = ModelStore(baseDirectory: base)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data().write(to: store.modelsDirectory.appendingPathComponent("a.gguf"))
        #expect(store.uniqueFileName(for: "a.gguf") == "a-2.gguf")
        #expect(store.uniqueFileName(for: "b.gguf") == "b.gguf")
    }
}
