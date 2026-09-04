import Foundation
import Observation
import os

/// User preferences, persisted in `UserDefaults`. Every key has a documented default and
/// the privacy-sensitive ones default to off.
@Observable
final class SettingsStore {
    enum Key: String, CaseIterable {
        case hasCompletedOnboarding
        case defaultModelRef
        case defaultPersonaID
        case storeConversations
        case catalogUpdates
        case catalogLastChecked
        case crashReports
        case wifiOnlyDownloads
        case requireAppLock
        case contextLength
        case gpuLayers
        case threadCount
        case keepModelLoaded
        case idleUnloadMinutes
        case flashAttention
        case sendWithEnter
        case toolsEnabled
        case dynamicToolCalling
        case showToolCalls
        case showTokenCounter
        case verboseLogging
        case bytesSentMonthKey
        case bytesSentThisMonth
        case bytesSentTotal
        case inspectorVisible
        case showMenuBarExtra
    }

    enum FlashAttentionMode: String, CaseIterable, Identifiable {
        case auto, on, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Automatic"
            case .on: return "On"
            case .off: return "Off"
            }
        }
        var boolValue: Bool? {
            switch self {
            case .auto: return nil
            case .on: return true
            case .off: return false
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    static var defaultContextLength: Int {
        #if os(macOS)
        return 8192
        #else
        return 4096
        #endif
    }

    static let contextLengthChoices = [2048, 4096, 8192, 16384, 32768]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = Self.bool(defaults, .hasCompletedOnboarding, default: false)
        defaultModelRefRaw = defaults.string(forKey: Key.defaultModelRef.rawValue) ?? ModelRef.apple.rawValue
        defaultPersonaID = defaults.string(forKey: Key.defaultPersonaID.rawValue).flatMap(UUID.init(uuidString:))
        storeConversations = Self.bool(defaults, .storeConversations, default: true)
        catalogUpdates = Self.bool(defaults, .catalogUpdates, default: false)
        catalogLastChecked = defaults.object(forKey: Key.catalogLastChecked.rawValue) as? Date
        crashReports = Self.bool(defaults, .crashReports, default: false)
        wifiOnlyDownloads = Self.bool(defaults, .wifiOnlyDownloads, default: true)
        requireAppLock = Self.bool(defaults, .requireAppLock, default: false)
        contextLength = defaults.object(forKey: Key.contextLength.rawValue) as? Int ?? Self.defaultContextLength
        gpuLayers = defaults.object(forKey: Key.gpuLayers.rawValue) as? Int ?? -1
        threadCount = defaults.object(forKey: Key.threadCount.rawValue) as? Int ?? 0
        keepModelLoaded = Self.bool(defaults, .keepModelLoaded, default: true)
        idleUnloadMinutes = defaults.object(forKey: Key.idleUnloadMinutes.rawValue) as? Int ?? 10
        flashAttention = FlashAttentionMode(rawValue: defaults.string(forKey: Key.flashAttention.rawValue) ?? "") ?? .auto
        sendWithEnter = Self.bool(defaults, .sendWithEnter, default: true)
        toolsEnabled = Self.bool(defaults, .toolsEnabled, default: true)
        dynamicToolCalling = Self.bool(defaults, .dynamicToolCalling, default: true)
        showToolCalls = Self.bool(defaults, .showToolCalls, default: false)
        showTokenCounter = Self.bool(defaults, .showTokenCounter, default: true)
        verboseLogging = Self.bool(defaults, .verboseLogging, default: false)
        bytesSentMonthKey = defaults.string(forKey: Key.bytesSentMonthKey.rawValue) ?? Self.currentMonthKey()
        bytesSentThisMonth = defaults.object(forKey: Key.bytesSentThisMonth.rawValue) as? Int64 ?? 0
        bytesSentTotal = defaults.object(forKey: Key.bytesSentTotal.rawValue) as? Int64 ?? 0
        inspectorVisible = Self.bool(defaults, .inspectorVisible, default: true)
        showMenuBarExtra = Self.bool(defaults, .showMenuBarExtra, default: true)
        rolloverMonthIfNeeded()
    }

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding.rawValue) } }
    var defaultModelRefRaw: String { didSet { defaults.set(defaultModelRefRaw, forKey: Key.defaultModelRef.rawValue) } }
    var defaultPersonaID: UUID? { didSet { defaults.set(defaultPersonaID?.uuidString, forKey: Key.defaultPersonaID.rawValue) } }
    var storeConversations: Bool { didSet { defaults.set(storeConversations, forKey: Key.storeConversations.rawValue) } }
    var catalogUpdates: Bool { didSet { defaults.set(catalogUpdates, forKey: Key.catalogUpdates.rawValue) } }
    var catalogLastChecked: Date? { didSet { defaults.set(catalogLastChecked, forKey: Key.catalogLastChecked.rawValue) } }
    var crashReports: Bool { didSet { defaults.set(crashReports, forKey: Key.crashReports.rawValue) } }
    var wifiOnlyDownloads: Bool { didSet { defaults.set(wifiOnlyDownloads, forKey: Key.wifiOnlyDownloads.rawValue) } }
    var requireAppLock: Bool { didSet { defaults.set(requireAppLock, forKey: Key.requireAppLock.rawValue) } }
    var contextLength: Int { didSet { defaults.set(contextLength, forKey: Key.contextLength.rawValue) } }
    var gpuLayers: Int { didSet { defaults.set(gpuLayers, forKey: Key.gpuLayers.rawValue) } }
    var threadCount: Int { didSet { defaults.set(threadCount, forKey: Key.threadCount.rawValue) } }
    var keepModelLoaded: Bool { didSet { defaults.set(keepModelLoaded, forKey: Key.keepModelLoaded.rawValue) } }
    var idleUnloadMinutes: Int { didSet { defaults.set(idleUnloadMinutes, forKey: Key.idleUnloadMinutes.rawValue) } }
    var flashAttention: FlashAttentionMode { didSet { defaults.set(flashAttention.rawValue, forKey: Key.flashAttention.rawValue) } }
    var sendWithEnter: Bool { didSet { defaults.set(sendWithEnter, forKey: Key.sendWithEnter.rawValue) } }
    /// Master switch for tool calling. Off means no tool is offered to any model.
    var toolsEnabled: Bool { didSet { defaults.set(toolsEnabled, forKey: Key.toolsEnabled.rawValue) } }
    /// Offers the library through one dispatcher tool the model has to name, instead of writing
    /// every tool's schema into the context window up front. See `DynamicToolGateway`.
    var dynamicToolCalling: Bool { didSet { defaults.set(dynamicToolCalling, forKey: Key.dynamicToolCalling.rawValue) } }
    /// Whether a tool call appears as a card in the transcript. Off by default: the call is a
    /// mechanism, not part of the answer, and on a phone the cards crowd out the reply.
    var showToolCalls: Bool { didSet { defaults.set(showToolCalls, forKey: Key.showToolCalls.rawValue) } }
    var showTokenCounter: Bool { didSet { defaults.set(showTokenCounter, forKey: Key.showTokenCounter.rawValue) } }
    var verboseLogging: Bool { didSet { defaults.set(verboseLogging, forKey: Key.verboseLogging.rawValue) } }
    var bytesSentMonthKey: String { didSet { defaults.set(bytesSentMonthKey, forKey: Key.bytesSentMonthKey.rawValue) } }
    var bytesSentThisMonth: Int64 { didSet { defaults.set(bytesSentThisMonth, forKey: Key.bytesSentThisMonth.rawValue) } }
    var bytesSentTotal: Int64 { didSet { defaults.set(bytesSentTotal, forKey: Key.bytesSentTotal.rawValue) } }
    var inspectorVisible: Bool { didSet { defaults.set(inspectorVisible, forKey: Key.inspectorVisible.rawValue) } }
    /// macOS only: shows the status item, and keeps Sotto running when its window closes
    /// so that item still has an app behind it.
    var showMenuBarExtra: Bool { didSet { defaults.set(showMenuBarExtra, forKey: Key.showMenuBarExtra.rawValue) } }

    var defaultModelRef: ModelRef {
        get { ModelRef(rawValue: defaultModelRefRaw) ?? .apple }
        set { defaultModelRefRaw = newValue.rawValue }
    }

    /// Records bytes our own network requests sent. Called by the download manager and catalog refresh.
    func recordBytesSent(_ bytes: Int64) {
        guard bytes > 0 else { return }
        rolloverMonthIfNeeded()
        bytesSentThisMonth += bytes
        bytesSentTotal += bytes
        Log.privacy.info("Network accounting: +\(bytes) bytes sent (month total \(self.bytesSentThisMonth))")
    }

    func rolloverMonthIfNeeded(now: Date = .now) {
        let key = Self.currentMonthKey(now)
        if key != bytesSentMonthKey {
            bytesSentMonthKey = key
            bytesSentThisMonth = 0
        }
    }

    /// Reads a stored flag. A value passed on the command line (`-storeConversations NO`) arrives as
    /// a string, so the plain `as? Bool` cast would silently miss it and fall back to the default.
    static func bool(_ defaults: UserDefaults, _ key: Key, default fallback: Bool) -> Bool {
        guard let value = defaults.object(forKey: key.rawValue) else { return fallback }
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return (text as NSString).boolValue
        default: return fallback
        }
    }

    static func currentMonthKey(_ date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    /// Restores every preference to its default value. Conversations and models are untouched.
    func resetToDefaults() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        let fresh = SettingsStore(defaults: defaults)
        hasCompletedOnboarding = fresh.hasCompletedOnboarding
        defaultModelRefRaw = fresh.defaultModelRefRaw
        defaultPersonaID = fresh.defaultPersonaID
        storeConversations = fresh.storeConversations
        catalogUpdates = fresh.catalogUpdates
        catalogLastChecked = fresh.catalogLastChecked
        crashReports = fresh.crashReports
        wifiOnlyDownloads = fresh.wifiOnlyDownloads
        requireAppLock = fresh.requireAppLock
        contextLength = fresh.contextLength
        gpuLayers = fresh.gpuLayers
        threadCount = fresh.threadCount
        keepModelLoaded = fresh.keepModelLoaded
        idleUnloadMinutes = fresh.idleUnloadMinutes
        flashAttention = fresh.flashAttention
        sendWithEnter = fresh.sendWithEnter
        toolsEnabled = fresh.toolsEnabled
        dynamicToolCalling = fresh.dynamicToolCalling
        showToolCalls = fresh.showToolCalls
        showTokenCounter = fresh.showTokenCounter
        verboseLogging = fresh.verboseLogging
        inspectorVisible = fresh.inspectorVisible
        showMenuBarExtra = fresh.showMenuBarExtra
    }
}
