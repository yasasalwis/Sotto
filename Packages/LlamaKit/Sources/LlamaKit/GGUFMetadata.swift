import Foundation
import llama

/// Reads the header of a GGUF file without loading any tensor data.
public enum GGUFMetadata {
    public static func read(at url: URL) throws -> LlamaModelInfo {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.fileNotFound(url.lastPathComponent)
        }
        let params = gguf_init_params(no_alloc: true, ctx: nil)
        guard let ctx = gguf_init_from_file(path, params) else {
            throw LlamaError.notAGGUFFile(url.lastPathComponent)
        }
        defer { gguf_free(ctx) }

        let architecture = string(ctx, "general.architecture") ?? "unknown"
        let name = string(ctx, "general.name") ?? url.deletingPathExtension().lastPathComponent
        let fileType = uint32(ctx, "general.file_type")
        let quantization = fileType.map(quantizationName) ?? "unknown"
        let contextLength = uint32(ctx, "\(architecture).context_length").map(Int.init) ?? 0
        let blockCount = uint32(ctx, "\(architecture).block_count").map(Int.init) ?? 0
        let hasTemplate = string(ctx, "tokenizer.chat_template") != nil
        let tensorCount = Int(gguf_get_n_tensors(ctx))

        var parameterCount: UInt64 = 0
        for index in 0..<gguf_get_n_tensors(ctx) {
            let type = gguf_get_tensor_type(ctx, index)
            let bytes = UInt64(gguf_get_tensor_size(ctx, index))
            let typeSize = UInt64(ggml_type_size(type))
            let blockSize = UInt64(ggml_blck_size(type))
            guard typeSize > 0 else { continue }
            parameterCount += bytes / typeSize * blockSize
        }

        let sizeLabel = string(ctx, "general.size_label") ?? parameterLabel(for: parameterCount)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        return LlamaModelInfo(
            name: name,
            architecture: architecture,
            quantization: quantization,
            parameterLabel: sizeLabel,
            parameterCount: parameterCount,
            fileSizeBytes: fileSize,
            trainingContextLength: contextLength,
            blockCount: blockCount,
            hasChatTemplate: hasTemplate,
            formatVersion: gguf_get_version(ctx),
            tensorCount: tensorCount
        )
    }

    /// Human-readable label such as "7B" or "1.7B".
    public static func parameterLabel(for count: UInt64) -> String {
        guard count > 0 else { return "—" }
        let billions = Double(count) / 1_000_000_000
        if billions >= 10 {
            return "\(Int(billions.rounded()))B"
        }
        if billions >= 1 {
            let rounded = (billions * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))B" : "\(rounded)B"
        }
        let millions = Double(count) / 1_000_000
        return "\(Int(millions.rounded()))M"
    }

    /// Maps `general.file_type` (a `llama_ftype`) to the conventional quantization name.
    public static func quantizationName(for fileType: UInt32) -> String {
        switch fileType {
        case 0: return "F32"
        case 1: return "F16"
        case 2: return "Q4_0"
        case 3: return "Q4_1"
        case 7: return "Q8_0"
        case 8: return "Q5_0"
        case 9: return "Q5_1"
        case 10: return "Q2_K"
        case 11: return "Q3_K_S"
        case 12: return "Q3_K_M"
        case 13: return "Q3_K_L"
        case 14: return "Q4_K_S"
        case 15: return "Q4_K_M"
        case 16: return "Q5_K_S"
        case 17: return "Q5_K_M"
        case 18: return "Q6_K"
        case 19: return "IQ2_XXS"
        case 20: return "IQ2_XS"
        case 21: return "Q2_K_S"
        case 22: return "IQ3_XS"
        case 23: return "IQ3_XXS"
        case 24: return "IQ1_S"
        case 25: return "IQ4_NL"
        case 26: return "IQ3_S"
        case 27: return "IQ3_M"
        case 28: return "IQ2_S"
        case 29: return "IQ2_M"
        case 30: return "IQ4_XS"
        case 31: return "IQ1_M"
        case 32: return "BF16"
        case 36: return "TQ1_0"
        case 37: return "TQ2_0"
        case 38: return "MXFP4"
        case 39: return "NVFP4"
        case 40: return "Q1_0"
        case 41: return "Q2_0"
        case 1024: return "unknown"
        default: return "type \(fileType)"
        }
    }

    private static func string(_ ctx: OpaquePointer, _ key: String) -> String? {
        let id = gguf_find_key(ctx, key)
        guard id >= 0, gguf_get_kv_type(ctx, id) == GGUF_TYPE_STRING, let value = gguf_get_val_str(ctx, id) else {
            return nil
        }
        return String(cString: value)
    }

    private static func uint32(_ ctx: OpaquePointer, _ key: String) -> UInt32? {
        let id = gguf_find_key(ctx, key)
        guard id >= 0 else { return nil }
        switch gguf_get_kv_type(ctx, id) {
        case GGUF_TYPE_UINT32: return gguf_get_val_u32(ctx, id)
        case GGUF_TYPE_INT32: return UInt32(clamping: gguf_get_val_i32(ctx, id))
        case GGUF_TYPE_UINT64: return UInt32(clamping: gguf_get_val_u64(ctx, id))
        default: return nil
        }
    }
}
