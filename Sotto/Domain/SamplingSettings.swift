import Foundation

/// The effective sampling parameters for one request, resolved from persona defaults
/// and per-conversation overrides.
struct SamplingSettings: Hashable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    static let `default` = SamplingSettings(temperature: 0.7, topP: 0.9, maxTokens: 1024)

    static func resolve(persona: Persona?, conversation: Conversation?) -> SamplingSettings {
        var settings = SamplingSettings.default
        if let persona {
            settings.temperature = persona.temperature
            settings.topP = persona.topP
            settings.maxTokens = persona.maxTokens
        }
        if let conversation {
            if let temperature = conversation.temperatureOverride { settings.temperature = temperature }
            if let topP = conversation.topPOverride { settings.topP = topP }
            if let maxTokens = conversation.maxTokensOverride { settings.maxTokens = maxTokens }
        }
        settings.temperature = min(max(settings.temperature, Persona.temperatureRange.lowerBound), Persona.temperatureRange.upperBound)
        settings.topP = min(max(settings.topP, Persona.topPRange.lowerBound), Persona.topPRange.upperBound)
        settings.maxTokens = min(max(settings.maxTokens, Persona.maxTokensRange.lowerBound), Persona.maxTokensRange.upperBound)
        return settings
    }
}
