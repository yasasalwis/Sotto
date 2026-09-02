import LlamaKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case privacy = "Privacy"
    case performance = "Performance"
    case shortcuts = "Shortcuts"
    case advanced = "Advanced"
    var id: String { rawValue }
}

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var pane: SettingsPane = .privacy

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { item in
                    Button {
                        pane = item
                    } label: {
                        Text(item.rawValue)
                            .font(Theme.Fonts.sans(14, weight: pane == item ? .medium : .regular))
                            .foregroundStyle(pane == item ? Theme.Colors.ink : Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(pane == item ? Theme.Colors.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(PlainRowButtonStyle())
                    .accessibilityIdentifier("settings.pane.\(item.rawValue.lowercased())")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
            .frame(width: 236)
            .background(Theme.Colors.panel)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.Colors.hairlinePanel).frame(width: 1) }
            ScrollView {
                paneContent
                    .padding(.horizontal, 56)
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.Colors.surface)
        #else
        List {
            NavigationLink("General") { SettingsPage(pane: .general) }
            NavigationLink("Models") { SettingsPage(pane: .models) }
            NavigationLink("Privacy") { SettingsPage(pane: .privacy) }
            NavigationLink("Performance") { SettingsPage(pane: .performance) }
            NavigationLink("Advanced") { SettingsPage(pane: .advanced) }
        }
        .font(Theme.Fonts.sans(15))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        #endif
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general: GeneralPane()
        case .models: ModelsPane()
        case .privacy: PrivacyPane()
        case .performance: PerformancePane()
        case .shortcuts: ShortcutsPane()
        case .advanced: AdvancedPane()
        }
    }
}

#if os(iOS)
struct SettingsPage: View {
    let pane: SettingsPane

    var body: some View {
        ScrollView {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .models: ModelsPane()
                case .privacy: PrivacyPane()
                case .performance: PerformancePane()
                case .shortcuts: ShortcutsPane()
                case .advanced: AdvancedPane()
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.panel)
        .navigationTitle(pane.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

// MARK: - Building blocks

struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            #if os(macOS)
            Text(title).font(Theme.Fonts.sans(24, weight: .medium)).tracking(-0.6).foregroundStyle(Theme.Colors.ink)
            #endif
            Text(subtitle)
                .font(Theme.Fonts.sans(14))
                .lineSpacing(5)
                .foregroundStyle(Theme.Colors.hint)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                SectionLabel(title).padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .card(radius: 12)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String? = nil
    var last = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Fonts.sans(14, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                if let detail {
                    Text(detail).font(Theme.Fonts.sans(13)).lineSpacing(4).foregroundStyle(Theme.Colors.hint).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
        }
    }
}

struct StatCard: View {
    let value: String
    let caption: String
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(Theme.Fonts.mono(26)).foregroundStyle(highlighted ? Theme.Colors.accent : Theme.Colors.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card(radius: 12, background: highlighted ? Theme.Colors.accentBackground : Theme.Colors.surface, border: highlighted ? Theme.Colors.accentSoft : Theme.Colors.border)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

    var body: some View {
        @Bindable var settings = services.settings
        VStack(alignment: .leading, spacing: 30) {
            PaneHeader(title: "General", subtitle: "Defaults for new chats. Each conversation can still pick its own model and persona.")
            SettingsGroup {
                SettingsRow(title: "Default model", detail: "Used for every new chat.") {
                    Picker("Default model", selection: $settings.defaultModelRefRaw) {
                        ForEach(ModelRegistry.all(installed: installed, runtime: services.runtime)) { descriptor in
                            Text(descriptor.name).tag(descriptor.ref.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent)
                }
                SettingsRow(title: "Default persona", detail: "Applied when a chat starts.") {
                    Picker("Default persona", selection: Binding(get: { settings.defaultPersonaID?.uuidString ?? "" }, set: { settings.defaultPersonaID = UUID(uuidString: $0) })) {
                        Text("None").tag("")
                        ForEach(personas) { persona in
                            Text(persona.name).tag(persona.id.uuidString)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent)
                }
                SettingsRow(title: "Send with Return", detail: "Off: Return adds a line and ⌘Return sends. Option-Return always adds a line.") {
                    Toggle("", isOn: $settings.sendWithEnter).toggleStyle(SottoToggleStyle()).labelsHidden()
                }
                SettingsRow(title: "Show token counter", detail: "The used / context figure under the composer.") {
                    Toggle("", isOn: $settings.showTokenCounter).toggleStyle(SottoToggleStyle()).labelsHidden()
                }
                SettingsRow(title: "Let models call tools", detail: "Tools run on this device unless you add one that makes an HTTPS request. Each tool can ask before it runs.", last: true) {
                    HStack(spacing: 10) {
                        Button("Manage…") { openTools() }.buttonStyle(SecondaryButtonStyle())
                        Toggle("", isOn: $settings.toolsEnabled).toggleStyle(SottoToggleStyle()).labelsHidden()
                    }
                }
            }
        }
    }
}

// MARK: - Models

extension GeneralPane {
    func openTools() {
        #if os(macOS)
        openWindow(id: WindowID.tools)
        #else
        services.state.sheet = .tools
        #endif
    }
}

struct ModelsPane: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openWindow) private var openWindow
    @Query private var installed: [InstalledModel]

    var body: some View {
        @Bindable var settings = services.settings
        VStack(alignment: .leading, spacing: 30) {
            PaneHeader(title: "Models", subtitle: "Imported GGUF weights live inside Sotto's own container and are excluded from backups.")
            SettingsGroup {
                SettingsRow(title: "Library", detail: "\(installed.count) imported · \(Format.bytes(services.store.diskUsage(of: installed))) on disk") {
                    Button("Open library") {
                        #if os(macOS)
                        openWindow(id: WindowID.library)
                        #else
                        services.state.sheet = .library
                        #endif
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                SettingsRow(title: "Context length", detail: "Tokens the model keeps in view. Larger windows use more memory.") {
                    Picker("Context", selection: $settings.contextLength) {
                        ForEach(SettingsStore.contextLengthChoices, id: \.self) { value in
                            Text(Format.contextLength(value)).tag(value)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent)
                }
                SettingsRow(title: "Keep model loaded", detail: "Off: unload after the idle period below to free memory.") {
                    Toggle("", isOn: $settings.keepModelLoaded).toggleStyle(SottoToggleStyle()).labelsHidden()
                }
                SettingsRow(title: "Unload after", detail: "Minutes of inactivity before weights are released.", last: true) {
                    Picker("Unload after", selection: $settings.idleUnloadMinutes) {
                        ForEach([2, 5, 10, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent).disabled(settings.keepModelLoaded)
                }
            }
            #if os(macOS)
            HStack(spacing: 12) {
                Button("Show models folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([services.store.modelsDirectory])
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Import GGUF…") { services.state.isImportingModel = true }.buttonStyle(SecondaryButtonStyle())
            }
            #endif
        }
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query private var installed: [InstalledModel]
    @Query private var conversations: [Conversation]
    @State private var confirmErase = false
    @State private var exporting = false
    @State private var exportDocument: ExportDocument?
    @State private var storeNotice = false

    private var messageCount: Int { PersistenceController.messageCount(context: context) }

    var body: some View {
        @Bindable var settings = services.settings
        VStack(alignment: .leading, spacing: 30) {
            #if os(iOS)
            PaneHeader(title: "Privacy", subtitle: "Sotto makes no network requests except model downloads and tools you start. Everything below is off unless you turn it on.")
            #else
            PaneHeader(title: "Privacy", subtitle: "Sotto makes no network requests except model downloads you start. Everything below is off unless you turn it on.")
            #endif
            SettingsGroup(title: platformNetworkTitle) {
                #if os(iOS)
                SettingsRow(title: "Downloads on Wi-Fi only", detail: "Catalog downloads pause on cellular.") {
                    Toggle("", isOn: $settings.wifiOnlyDownloads).toggleStyle(SottoToggleStyle()).labelsHidden()
                        .onChange(of: settings.wifiOnlyDownloads) { _, _ in services.downloads.updateCellularPolicy() }
                }
                #endif
                SettingsRow(title: "Store conversations", detail: storeDetail) {
                    Toggle("", isOn: $settings.storeConversations).toggleStyle(SottoToggleStyle()).labelsHidden()
                        .onChange(of: settings.storeConversations) { _, _ in storeNotice = true }
                }
                SettingsRow(title: "Model catalog updates", detail: "Check Hugging Face weekly for new quantizations of the curated models.") {
                    Toggle("", isOn: $settings.catalogUpdates).toggleStyle(SottoToggleStyle()).labelsHidden()
                }
                SettingsRow(title: "Crash reports", detail: "Never enabled by default. Reports stay on this device; you review them in Advanced before sharing anything.", last: true) {
                    Toggle("", isOn: $settings.crashReports).toggleStyle(SottoToggleStyle()).labelsHidden()
                        .onChange(of: settings.crashReports) { _, value in services.diagnostics.setEnabled(value) }
                }
            }
            #if os(iOS)
            SettingsGroup(title: "On this device") {
                SettingsRow(title: "Conversations") {
                    MonoText("\(Format.integer(messageCount)) messages · protected", size: 12)
                }
                SettingsRow(title: "\(AppLock.biometryLabel) to open") {
                    Toggle("", isOn: $settings.requireAppLock).toggleStyle(SottoToggleStyle()).labelsHidden().disabled(!AppLock.isAvailable)
                }
                SettingsRow(title: "Model weights", last: true) {
                    Button { services.state.sheet = .library } label: {
                        MonoText("\(Format.bytes(services.store.diskUsage(of: installed))) ›", size: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            #else
            HStack(spacing: 14) {
                StatCard(value: Format.bytes(settings.bytesSentThisMonth), caption: "Data sent this month", highlighted: true)
                StatCard(value: Format.integer(messageCount), caption: "Messages, all on-device")
                StatCard(value: Format.bytes(services.store.diskUsage(of: installed)), caption: "Model weights stored")
            }
            SettingsGroup {
                SettingsRow(title: "Require \(AppLock.biometryLabel) to open", detail: AppLock.isAvailable ? "Locks Sotto when it goes to the background." : "No biometric or passcode policy is available on this Mac.", last: true) {
                    Toggle("", isOn: $settings.requireAppLock).toggleStyle(SottoToggleStyle()).labelsHidden().disabled(!AppLock.isAvailable)
                }
            }
            #endif
            HStack(spacing: 12) {
                Button("Export all conversations") { prepareExport() }
                    .buttonStyle(SecondaryButtonStyle(size: 13, horizontalPadding: 15, verticalPadding: 9))
                    .disabled(conversations.isEmpty)
                Button("Erase all data…") { confirmErase = true }
                    .buttonStyle(SecondaryButtonStyle(size: 13, horizontalPadding: 15, verticalPadding: 9, foreground: Theme.Colors.danger, border: Theme.Colors.dangerBorder))
                    .accessibilityIdentifier("privacy.erase")
            }
            Text("Sotto has no account and no server. Erasing here erases everything.")
                .font(Theme.Fonts.sans(12)).foregroundStyle(Theme.Colors.faint)
        }
        .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase conversations, models and settings", role: .destructive) { erase() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every conversation, persona, imported model and preference on this device. There is no copy anywhere else.")
        }
        .alert("Takes effect after relaunch", isPresented: $storeNotice) {
            Button("OK") {}
        } message: {
            Text(settings.storeConversations ? "Conversations will be saved to disk starting next launch." : "From the next launch, conversations stay in memory and vanish when Sotto quits. Existing conversations remain on disk until you erase them.")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Sotto export") { result in
            if case .failure(let error) = result {
                services.state.showError("Export failed", error.localizedDescription)
            }
        }
    }

    private var platformNetworkTitle: String? {
        #if os(iOS)
        return "Network"
        #else
        return nil
        #endif
    }

    private var storeDetail: String {
        #if os(macOS)
        return "Saved in Sotto's sandboxed container under ~/Library/Containers, covered by FileVault when it's on."
        #else
        return "Saved in Sotto's container with Data Protection; unreadable until the device is unlocked once."
        #endif
    }

    private func prepareExport() {
        do {
            let export = ConversationExport.make(from: conversations)
            exportDocument = ExportDocument(data: try export.jsonData(), contentType: .json)
            exporting = true
        } catch {
            services.state.showError("Export failed", error.localizedDescription)
        }
    }

    private func erase() {
        do {
            try services.eraseEverything()
        } catch {
            services.state.showError("Erase failed", error.localizedDescription)
        }
    }
}

// MARK: - Performance

struct PerformancePane: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings
        VStack(alignment: .leading, spacing: 30) {
            PaneHeader(title: "Performance", subtitle: "How imported models use this device. Apple Intelligence manages itself.")
            SettingsGroup {
                SettingsRow(title: "GPU offload", detail: DeviceCapabilities.isSimulator ? "The Simulator runs on the CPU only." : "Metal runs every layer on the GPU when possible.") {
                    Picker("GPU offload", selection: $settings.gpuLayers) {
                        Text("All layers").tag(-1)
                        Text("CPU only").tag(0)
                        ForEach([8, 16, 24, 32], id: \.self) { Text("\($0) layers").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent).disabled(DeviceCapabilities.isSimulator)
                }
                SettingsRow(title: "Threads", detail: "Automatic uses the performance cores (\(LlamaRuntime.recommendedThreadCount)).") {
                    Picker("Threads", selection: $settings.threadCount) {
                        Text("Automatic").tag(0)
                        ForEach(Array(stride(from: 2, through: max(2, ProcessInfo.processInfo.activeProcessorCount), by: 2)), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent)
                }
                SettingsRow(title: "Flash attention", detail: "Faster and lighter on memory for most models; automatic lets llama.cpp decide.", last: true) {
                    Picker("Flash attention", selection: $settings.flashAttention) {
                        ForEach(SettingsStore.FlashAttentionMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.Colors.accent)
                }
            }
            SettingsGroup(title: "This device") {
                SettingsRow(title: "Chip") { MonoText(DeviceCapabilities.chipName, size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "Memory") { MonoText("\(Format.bytes(DeviceCapabilities.physicalMemoryBytes)) total · \(Format.bytes(DeviceCapabilities.availableMemoryBytes())) available", size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "llama.cpp") { MonoText("\(LlamaRuntime.version) · Metal \(LlamaRuntime.supportsGPUOffload ? "on" : "off")", size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "Loaded model", last: true) { MonoText(services.runtime.state.label, size: 12, color: Theme.Colors.ink) }
            }
            Text("Changes apply the next time a model is loaded.")
                .font(Theme.Fonts.sans(12)).foregroundStyle(Theme.Colors.faint)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    private let shortcuts: [(String, String)] = [
        ("⌘N", "New chat"),
        ("⌘↩", "Send message"),
        ("⌥↩", "New line in the composer"),
        ("⌥⌘I", "Show or hide the inspector"),
        ("⌥⌘1 … ⌥⌘9", "Apply a persona by its slot"),
        ("⇧⌘L", "Model library"),
        ("⇧⌘K", "Compare two models"),
        ("⇧⌘P", "Presets & personas"),
        ("⇧⌘T", "Tools"),
        ("⇧⌘I", "Import a GGUF file"),
        ("⌘,", "Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            PaneHeader(title: "Shortcuts", subtitle: "Keyboard shortcuts on macOS and on iPad with a hardware keyboard.")
            SettingsGroup {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                    SettingsRow(title: item.1, last: index == shortcuts.count - 1) {
                        MonoText(item.0, size: 12, color: Theme.Colors.ink)
                    }
                }
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @Environment(AppServices.self) private var services
    @State private var reports: [URL] = []
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = services.settings
        VStack(alignment: .leading, spacing: 30) {
            PaneHeader(title: "Advanced", subtitle: "Diagnostics stay on this device. Logs go to the unified log under the subsystem lk.eonix.Sotto and never include prompts.")
            SettingsGroup {
                SettingsRow(title: "Verbose logging", detail: "Adds per-request timing to the unified log. Read it with Console or `log stream --predicate 'subsystem == \"lk.eonix.Sotto\"'`.") {
                    Toggle("", isOn: $settings.verboseLogging).toggleStyle(SottoToggleStyle()).labelsHidden()
                }
                SettingsRow(title: "Reset preferences", detail: "Restores every setting to its default. Conversations and models are untouched.", last: true) {
                    Button("Reset…") { confirmReset = true }.buttonStyle(SecondaryButtonStyle())
                }
            }
            SettingsGroup(title: "Diagnostic reports") {
                if reports.isEmpty {
                    SettingsRow(title: "No reports collected", detail: settings.crashReports ? "MetricKit delivers diagnostics after a crash or hang, usually within a day." : "Turn on Crash reports in Privacy to collect them.", last: true) { EmptyView() }
                } else {
                    ForEach(Array(reports.enumerated()), id: \.offset) { index, url in
                        SettingsRow(title: url.lastPathComponent, last: index == reports.count - 1) {
                            HStack(spacing: 8) {
                                ShareLink(item: url) { Text("Share").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.accent) }
                                Button("Delete") {
                                    try? FileManager.default.removeItem(at: url)
                                    reports = services.diagnostics.reports()
                                }
                                .buttonStyle(.plain).font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.danger)
                            }
                        }
                    }
                }
            }
            SettingsGroup(title: "About") {
                SettingsRow(title: "Version") { MonoText(Bundle.main.versionLabel, size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "Fonts") { MonoText("Geist · IBM Plex Mono (SIL OFL)", size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "Inference") { MonoText("FoundationModels · llama.cpp \(LlamaRuntime.version)", size: 12, color: Theme.Colors.ink) }
                SettingsRow(title: "Privacy policy") { LinkRow("Open", url: AppLinks.privacyPolicy) }
                SettingsRow(title: "Support") { LinkRow("Open", url: AppLinks.support) }
                SettingsRow(title: "Source code", last: true) { LinkRow("Open", url: AppLinks.sourceCode) }
            }
            SettingsGroup(title: "Generated text") {
                SettingsRow(title: "Models are not fact-checked", detail: AppLinks.generatedContentNotice, last: true) { EmptyView() }
            }
        }
        .onAppear { reports = services.diagnostics.reports() }
        .confirmationDialog("Reset all preferences?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { services.settings.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
