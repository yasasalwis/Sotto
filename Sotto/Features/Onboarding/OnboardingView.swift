import SwiftData
import SwiftUI
import os
import UniformTypeIdentifiers

struct OnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query private var installed: [InstalledModel]
    @State private var importing = false
    @State private var importError: String?
    @State private var isImporting = false

    private var appleAvailable: Bool { AppleIntelligenceEngine.isAvailable }
    private var availableMemory: UInt64 { DeviceCapabilities.availableMemoryBytes() }

    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            iosLayout
            #endif
        }
        .background(Theme.Colors.surface)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gguf, .data], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            importModel(url)
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                LogoMark(size: 52, radius: 15)
                Text("Your models. Your machine.")
                    .font(Theme.Fonts.sans(44, weight: .medium))
                    .tracking(-1.6)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sotto runs Apple's on-device foundation model and any GGUF weights you bring. No accounts, no telemetry, no upstream calls.")
                    .font(Theme.Fonts.sans(17))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Colors.muted)
                    .frame(maxWidth: 430, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    checklistRow(done: appleAvailable, text: appleAvailable ? "Apple Intelligence detected — 3B on-device, ready" : (AppleIntelligenceEngine.unavailableReason ?? "Apple Intelligence unavailable"))
                    checklistRow(done: true, text: "\(Format.bytes(availableMemory)) free memory — \(DeviceCapabilities.headroomLabel(availableBytes: availableMemory))")
                    checklistRow(done: !installed.isEmpty, text: installed.isEmpty ? "No open-source models imported yet" : "\(installed.count) open-source model\(installed.count == 1 ? "" : "s") imported")
                }
                .padding(.top, 8)
                HStack(spacing: 12) {
                    Button(appleAvailable ? "Start with Apple Intelligence" : "Start chatting") { finish() }
                        .buttonStyle(PrimaryButtonStyle(size: 15, horizontalPadding: 24, verticalPadding: 12, radius: 9))
                        .accessibilityIdentifier("onboarding.start")
                    Button(isImporting ? "Importing…" : "Import a model…") { importing = true }
                        .buttonStyle(SecondaryButtonStyle(size: 15, horizontalPadding: 24, verticalPadding: 12, radius: 9))
                        .disabled(isImporting)
                }
                .padding(.top, 20)
                generatedContentNotice
                    .frame(maxWidth: 430, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 76)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                SectionLabel("What stays local", color: Theme.Colors.mutedLight, size: 11)
                VStack(spacing: 0) {
                    localRow("Conversations", value: services.settings.storeConversations ? "on disk" : "in memory", accent: true)
                    localRow("Inference", value: "on device", accent: true)
                    localRow("Model downloads", value: "network", accent: false)
                    localRow("Analytics", value: "none", accent: false, last: true)
                }
                .card(radius: 12, border: Theme.Colors.borderSidebar)
                Text("Apple's Foundation Models framework runs entirely on this Mac, and imported models run through llama.cpp. Nothing you type leaves the machine unless a tool you set up asks for it.")
                    .font(Theme.Fonts.sans(13))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.Colors.hint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 72)
            .frame(maxWidth: 520, maxHeight: .infinity, alignment: .leading)
            .background(Theme.Colors.sidebar)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.Colors.border).frame(width: 1) }
        }
    }

    private func localRow(_ label: String, value: String, accent: Bool, last: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.Fonts.sans(14)).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            MonoText(value, size: 12, color: accent ? Theme.Colors.accent : Theme.Colors.hint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
        }
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                LogoMark(size: 56, radius: 16)
                Text("Your models.\nYour phone.")
                    .font(Theme.Fonts.sans(36, weight: .medium))
                    .tracking(-1.3)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.Colors.ink)
                Text("Chat with Apple's on-device model or open-source weights you bring. Airplane mode changes nothing.")
                    .font(Theme.Fonts.sans(16))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Colors.muted)
                VStack(spacing: 10) {
                    statusCard(
                        highlighted: appleAvailable,
                        title: "Apple Intelligence",
                        detail: appleAvailable ? "3B on-device · ready" : (AppleIntelligenceEngine.unavailableReason ?? "unavailable")
                    )
                    statusCard(
                        highlighted: !installed.isEmpty,
                        title: "Open-source models",
                        detail: installed.isEmpty ? "none imported · \(Format.bytes(services.store.freeDiskBytes)) free" : "\(installed.count) imported · \(Format.bytes(services.store.freeDiskBytes)) free"
                    )
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 30)
            .padding(.top, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: 12) {
                generatedContentNotice
                Button("Start chatting") { finish() }
                    .buttonStyle(PrimaryButtonStyle(size: 16, horizontalPadding: 16, verticalPadding: 16, radius: 14, fullWidth: true))
                    .accessibilityIdentifier("onboarding.start")
                Button(isImporting ? "Importing…" : "Import a model instead") { importing = true }
                    .font(Theme.Fonts.sans(15))
                    .foregroundStyle(Theme.Colors.accent)
                    .disabled(isImporting)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
    }

    private func statusCard(highlighted: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            StatusDot(color: highlighted ? Theme.Colors.accent : Theme.Colors.dotDim, size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                MonoText(detail, size: 11, color: highlighted ? Theme.Colors.accent : Theme.Colors.placeholder)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .card(radius: 13, background: highlighted ? Theme.Colors.accentBackground : Theme.Colors.surface, border: highlighted ? Theme.Colors.accentSoft : Theme.Colors.border)
    }
    #endif

    // MARK: - Shared

    /// Sotto neither reviews nor filters what a model writes, and a person meeting the app for
    /// the first time should be told so before their first message rather than after it.
    private var generatedContentNotice: some View {
        Text(AppLinks.generatedContentNotice)
            .font(Theme.Fonts.sans(12))
            .lineSpacing(4)
            .foregroundStyle(Theme.Colors.faint)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("onboarding.generatedContentNotice")
    }

    private func checklistRow(done: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(done ? Theme.Colors.accentSoft : Theme.Colors.hairlinePanel)
                .frame(width: 18, height: 18)
                .overlay(
                    Text(done ? "✓" : "·")
                        .font(.system(size: 11))
                        .foregroundStyle(done ? Theme.Colors.accent : Theme.Colors.hint)
                )
                .padding(.top, 2)
            Text(text)
                .font(Theme.Fonts.sans(15))
                .lineSpacing(4)
                .foregroundStyle(done ? Theme.Colors.textSecondary : Theme.Colors.hint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish() {
        services.settings.defaultModelRef = ModelRegistry.preferredDefault(installed: installed, settings: services.settings)
        services.settings.hasCompletedOnboarding = true
        Log.app.info("Onboarding completed")
    }

    private func importModel(_ url: URL) {
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let record = try await services.store.importModel(from: url, into: context)
                services.settings.defaultModelRef = record.modelRef
                finish()
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
