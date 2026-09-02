import Foundation
import Testing
@testable import LlamaKit

struct GGUFMetadataTests {
    @Test func readsHeaderOfSyntheticFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-test-\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: url) }
        try SyntheticGGUF.write(to: url, metadata: [
            ("general.architecture", .string("llama")),
            ("general.name", .string("Synthetic Test Model")),
            ("general.file_type", .uint32(15)),
            ("general.size_label", .string("3B")),
            ("llama.context_length", .uint32(4096)),
            ("llama.block_count", .uint32(2)),
            ("tokenizer.chat_template", .string("{{ messages }}")),
        ])
        let info = try GGUFMetadata.read(at: url)
        #expect(info.name == "Synthetic Test Model")
        #expect(info.architecture == "llama")
        #expect(info.quantization == "Q4_K_M")
        #expect(info.parameterLabel == "3B")
        #expect(info.trainingContextLength == 4096)
        #expect(info.blockCount == 2)
        #expect(info.hasChatTemplate)
        #expect(info.tensorCount == 0)
        #expect(info.formatVersion == 3)
    }

    @Test func rejectsNonGGUFFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-test-\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a model".utf8).write(to: url)
        #expect(throws: LlamaError.notAGGUFFile(url.lastPathComponent)) {
            try GGUFMetadata.read(at: url)
        }
    }

    @Test func missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).gguf")
        #expect(throws: LlamaError.fileNotFound(url.lastPathComponent)) {
            try GGUFMetadata.read(at: url)
        }
    }

    @Test func parameterLabels() {
        #expect(GGUFMetadata.parameterLabel(for: 0) == "—")
        #expect(GGUFMetadata.parameterLabel(for: 494_000_000) == "494M")
        #expect(GGUFMetadata.parameterLabel(for: 1_700_000_000) == "1.7B")
        #expect(GGUFMetadata.parameterLabel(for: 3_090_000_000) == "3.1B")
        #expect(GGUFMetadata.parameterLabel(for: 7_000_000_000) == "7B")
        #expect(GGUFMetadata.parameterLabel(for: 70_600_000_000) == "71B")
    }

    @Test func quantizationNames() {
        #expect(GGUFMetadata.quantizationName(for: 17) == "Q5_K_M")
        #expect(GGUFMetadata.quantizationName(for: 1) == "F16")
        #expect(GGUFMetadata.quantizationName(for: 999) == "type 999")
    }
}

struct UTF8AssemblerTests {
    @Test func holdsBackIncompleteSequence() {
        var assembler = UTF8Assembler()
        let euro = Array("€".utf8) // E2 82 AC
        #expect(assembler.append(euro[0..<1]) == nil)
        #expect(assembler.append(euro[1..<2]) == nil)
        #expect(assembler.append(euro[2..<3]) == "€")
        #expect(!assembler.hasPendingBytes)
    }

    @Test func releasesCompletePrefix() {
        var assembler = UTF8Assembler()
        let bytes = Array("ab".utf8) + Array("é".utf8).prefix(1)
        #expect(assembler.append(bytes) == "ab")
        #expect(assembler.hasPendingBytes)
        #expect(assembler.flush() == "\u{FFFD}")
    }

    @Test func plainASCIIPassesThrough() {
        var assembler = UTF8Assembler()
        #expect(assembler.append(Array("hello".utf8)) == "hello")
    }
}

struct ChatMLTemplateTests {
    @Test func rendersRolesInOrder() {
        let text = ChatMLTemplate.render([
            LlamaChatMessage(role: "system", content: "Be brief."),
            LlamaChatMessage(role: "user", content: "Hi"),
        ])
        #expect(text == "<|im_start|>system\nBe brief.<|im_end|>\n<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n")
    }
}

struct LlamaRuntimeTests {
    @Test func reportsVersionAndThreads() {
        #expect(!LlamaRuntime.version.isEmpty)
        #expect(LlamaRuntime.recommendedThreadCount >= 1)
    }
}
