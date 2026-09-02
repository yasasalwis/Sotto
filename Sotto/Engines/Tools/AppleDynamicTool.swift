import Foundation
import FoundationModels

/// Bridges one `ToolDefinition` into Apple's native tool-calling protocol so the system model can
/// call it directly. Arguments arrive as `GeneratedContent` and are flattened to a plain dictionary.
nonisolated struct AppleDynamicTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let runner: ToolRunner

    init(spec: ToolSpec, runner: ToolRunner) throws {
        self.name = spec.name
        self.description = spec.description
        self.runner = runner
        self.parameters = try Self.schema(for: spec)
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let json = Self.json(from: Self.dictionary(from: arguments))
        let result = await runner.run(ToolCallRequest(name: name, argumentsJSON: json))
        return result.text
    }

    static func schema(for spec: ToolSpec) throws -> GenerationSchema {
        let properties = spec.parameters.map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.summary.isEmpty ? nil : parameter.summary,
                schema: valueSchema(for: parameter.type),
                isOptional: !parameter.isRequired
            )
        }
        let root = DynamicGenerationSchema(
            name: spec.name,
            description: spec.description,
            properties: properties
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func valueSchema(for type: ToolParameterType) -> DynamicGenerationSchema {
        switch type {
        case .string: return DynamicGenerationSchema(type: String.self)
        case .number: return DynamicGenerationSchema(type: Double.self)
        case .boolean: return DynamicGenerationSchema(type: Bool.self)
        }
    }

    /// Flattens generated content into JSON-compatible values.
    static func dictionary(from content: GeneratedContent) -> [String: Any] {
        guard case .structure(let properties, _) = content.kind else { return [:] }
        return properties.reduce(into: [String: Any]()) { result, entry in
            if let value = plainValue(entry.value) {
                result[entry.key] = value
            }
        }
    }

    static func plainValue(_ content: GeneratedContent) -> Any? {
        switch content.kind {
        case .null: return nil
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let items): return items.compactMap { plainValue($0) }
        case .structure(let properties, _):
            return properties.reduce(into: [String: Any]()) { result, entry in
                if let value = plainValue(entry.value) { result[entry.key] = value }
            }
        }
    }

    static func json(from arguments: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
