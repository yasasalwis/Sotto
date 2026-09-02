import SwiftData
import SwiftUI

struct CatalogListView: View {
    @Environment(AppServices.self) private var services
    @Query private var installed: [InstalledModel]
    @Query private var downloads: [ModelDownload]
    @State private var errorMessage: String?
    @State private var refreshing = false
    @State private var lastRefresh = CatalogRefresher.loadLastResult()

    private var availableMemory: UInt64 { DeviceCapabilities.availableMemoryBytes() }

    var body: some View {
        VStack(spacing: 10) {
            header
            ForEach(services.catalog.entries) { entry in
                row(entry)
            }
            Text("Downloads come straight from Hugging Face over HTTPS. Sotto sends only the request itself and counts those bytes on the Privacy page.")
                .font(Theme.Fonts.sans(12))
                .foregroundStyle(Theme.Colors.faint)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .alert("Couldn't start download", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                MonoText("curated catalog · \(services.catalog.entries.count) models · updated \(services.catalog.updatedAt)", size: 11)
                if let lastRefresh {
                    MonoText("checked \(Format.shortDate(lastRefresh.checkedAt)) · \(lastRefresh.newQuantizationCount) other quantizations listed upstream", size: 11, color: Theme.Colors.accent)
                } else if services.settings.catalogUpdates {
                    MonoText("weekly checks on · not checked yet", size: 11, color: Theme.Colors.faint)
                } else {
                    MonoText("weekly checks off (Settings › Privacy)", size: 11, color: Theme.Colors.faint)
                }
            }
            Spacer()
            if services.settings.catalogUpdates {
                Button(refreshing ? "Checking…" : "Check now") {
                    refreshing = true
                    Task {
                        lastRefresh = await CatalogRefresher.refresh(catalog: services.catalog, settings: services.settings) ?? lastRefresh
                        refreshing = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
                .disabled(refreshing)
            }
        }
        .padding(.bottom, 6)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        let installedMatch = installed.first { $0.catalogID == entry.id || $0.fileName == entry.fileName }
        let download = downloads.first { $0.catalogID == entry.id }
        let fits = UInt64(entry.estimatedMemoryBytes) <= availableMemory
        return HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surfaceMuted)
                .frame(width: 38, height: 38)
                .overlay(Text(entry.glyph).font(Theme.Fonts.mono(12)).foregroundStyle(Theme.Colors.muted))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.name).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    labelBadge(entry.quantization, accent: false)
                }
                Text(entry.summary).font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.hint).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    MonoText(Format.bytes(entry.sizeBytes), size: 11, color: Theme.Colors.ink)
                    MonoText("\(entry.parameterLabel) · \(Format.contextLength(entry.contextLength)) ctx", size: 11)
                        .lineLimit(1)
                }
                MonoText("\(entry.license) · \(entry.publisher)", size: 10, color: Theme.Colors.faint)
                    .lineLimit(2)
                if !fits, installedMatch == nil {
                    MonoText("needs about \(Format.bytes(entry.estimatedMemoryBytes)) · not enough memory right now", size: 11, color: Theme.Colors.danger)
                }
            }
            Spacer()
            actionButton(entry: entry, installed: installedMatch, download: download)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card(radius: 12)
        .opacity(fits || installedMatch != nil ? 1 : 0.7)
        .accessibilityIdentifier("catalog.entry")
    }

    @ViewBuilder
    private func actionButton(entry: CatalogEntry, installed: InstalledModel?, download: ModelDownload?) -> some View {
        if installed != nil {
            MonoText("installed", size: 11, color: Theme.Colors.accent)
        } else if let download {
            VStack(alignment: .trailing, spacing: 6) {
                MonoText(download.state == .downloading ? Format.percent(services.downloads.live[download.id]?.fraction ?? download.fraction) : download.state.rawValue, size: 11, color: Theme.Colors.accent)
                if download.state == .paused || download.state == .failed {
                    Button("Resume") { services.downloads.resume(download) }
                        .buttonStyle(PrimaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
                } else {
                    Button("Pause") { services.downloads.pause(download) }
                        .buttonStyle(SecondaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
                }
            }
        } else {
            Button("Download") {
                do {
                    try services.downloads.start(entry)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(PrimaryButtonStyle(size: 12, horizontalPadding: 14, verticalPadding: 7, radius: 7))
            .accessibilityIdentifier("catalog.download")
        }
    }
}
