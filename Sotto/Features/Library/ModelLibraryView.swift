import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case downloading = "Downloading"
        case catalog = "Catalog"
        var id: String { rawValue }
    }

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @Query(sort: \ModelDownload.createdAt) private var downloads: [ModelDownload]
    @State private var tab: Tab = .installed
    @State private var importing = false
    @State private var pendingDelete: InstalledModel?
    @State private var errorMessage: String?
    @State private var dropTargeted = false

    private var diskUsage: Int64 { services.store.diskUsage(of: installed) }
    private var installedCount: Int { installed.count + (AppleIntelligenceEngine.isAvailable ? 1 : 0) }
    private var summary: String {
        "\(installedCount) installed · \(Format.bytes(diskUsage)) on disk · \(Format.bytes(services.store.freeDiskBytes)) free"
    }

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
        .confirmationDialog("Delete \(pendingDelete?.name ?? "model")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete weights from disk", role: .destructive) {
                if let model = pendingDelete { delete(model) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Conversations that used this model stay; they'll fall back to another model when you continue them.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Models")
                        .font(Theme.Fonts.sans(26, weight: .medium))
                        .tracking(-0.7)
                        .foregroundStyle(Theme.Colors.ink)
                    MonoText(summary, size: 12)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("Import GGUF…") { importing = true }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Browse catalog") { tab = .catalog }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 34)
            .padding(.bottom, 22)
            tabs
            ScrollView {
                VStack(spacing: 10) {
                    switch tab {
                    case .installed:
                        installedList
                    case .downloading:
                        downloadList
                    case .catalog:
                        CatalogListView()
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, 22)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var tabs: some View {
        HStack(spacing: 22) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(item.rawValue)
                            if item == .downloading, !downloads.isEmpty {
                                MonoText("\(downloads.count)", size: 10, color: Theme.Colors.accent)
                            }
                        }
                        .font(Theme.Fonts.sans(13, weight: tab == item ? .medium : .regular))
                        .foregroundStyle(tab == item ? Theme.Colors.ink : Theme.Colors.hint)
                        .padding(.bottom, 10)
                        Rectangle().fill(tab == item ? Theme.Colors.accent : Color.clear).frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.tab.\(item.rawValue.lowercased())")
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.page)
        .hairlineDivider()
    }

    private var installedList: some View {
        VStack(spacing: 10) {
            AppleModelRow()
            ForEach(installed) { model in
                InstalledModelRow(model: model, onDelete: { pendingDelete = model })
            }
            ForEach(downloads.filter { $0.state != .completed }) { download in
                DownloadRow(download: download)
            }
            Button {
                importing = true
            } label: {
                HStack(spacing: 6) {
                    Text("Drop a").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.faint)
                    MonoText(".gguf", size: 12)
                    Text("file here to import").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(dropTargeted ? Theme.Colors.accent : Theme.Colors.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            }
            .buttonStyle(PlainRowButtonStyle())
        }
    }

    private var downloadList: some View {
        VStack(spacing: 10) {
            if downloads.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing downloading").font(Theme.Fonts.sans(14, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    Text("Pick a model in the catalog to start a download. Downloads resume after relaunch.")
                        .font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.hint)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
            ForEach(downloads) { download in
                DownloadRow(download: download)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            if let direct = item as? URL { url = direct }
            guard let url else { return }
            Task { @MainActor in importModel(url) }
        }
        return true
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosLayout: some View {
        ScrollView {
            VStack(spacing: 10) {
                if tab == .catalog {
                    CatalogListView()
                } else {
                    AppleModelRow()
                    ForEach(installed) { model in
                        InstalledModelRow(model: model, onDelete: { pendingDelete = model })
                    }
                    ForEach(downloads) { download in
                        DownloadRow(download: download)
                    }
                    Button {
                        importing = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("Import a").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.faint)
                            MonoText(".gguf", size: 12)
                            Text("from Files").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.faint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.Colors.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }
                    .buttonStyle(PlainRowButtonStyle())
                    storageBar
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.panel)
        .navigationTitle(tab == .catalog ? "Catalog" : "Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Theme.Colors.textSecondary)
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(tab == .catalog ? "Catalog" : "Models").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(summary, size: 10)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if tab == .catalog {
                    Button("Done") { tab = .installed }.foregroundStyle(Theme.Colors.accent)
                } else {
                    Menu {
                        Button("Browse catalog") { tab = .catalog }
                        Button("Import from Files…") { importing = true }
                    } label: {
                        Image(systemName: "plus").foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityLabel("Add model")
                }
            }
        }
    }

    private var storageBar: some View {
        let free = services.store.freeDiskBytes
        let downloading = downloads.reduce(Int64(0)) { $0 + $1.receivedBytes }
        let total = max(diskUsage + downloading + free, 1)
        return HStack(spacing: 12) {
            SectionLabel("Storage", size: 11)
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.Colors.accent).frame(width: proxy.size.width * Double(diskUsage) / Double(total))
                    Rectangle().fill(Theme.Colors.barMid).frame(width: proxy.size.width * Double(downloading) / Double(total))
                    Rectangle().fill(Theme.Colors.hairlinePanel)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            MonoText(Format.bytes(diskUsage + downloading), size: 11, color: Theme.Colors.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(radius: 14)
    }
    #endif

    // MARK: - Actions

    private func importModel(_ url: URL) {
        Task {
            do {
                _ = try await services.store.importModel(from: url, into: context)
                tab = .installed
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ model: InstalledModel) {
        Task {
            if services.runtime.loadedModelID == model.id {
                await services.runtime.unload()
            }
            do {
                try services.store.delete(model, from: context)
                if services.settings.defaultModelRef == model.modelRef {
                    services.settings.defaultModelRef = .apple
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Rows

struct AppleModelRow: View {
    @Environment(AppServices.self) private var services

    private var descriptor: ModelDescriptor { ModelRegistry.appleDescriptor() }
    private var isDefault: Bool { services.settings.defaultModelRef == .apple }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 20) {
            ModelGlyph(descriptor: descriptor, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Apple Intelligence").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    labelBadge("SYSTEM", accent: true)
                }
                Text(descriptor.isAvailable ? "On-device foundation model · 3B params" : (descriptor.unavailableReason ?? "Unavailable"))
                    .font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.hint)
            }
            .frame(width: 290, alignment: .leading)
            MetricColumn(value: "—", caption: "Disk").frame(width: 110, alignment: .leading)
            MetricColumn(value: descriptor.measuredTokensPerSecond.map { Format.tokensPerSecond($0, approximate: true, fractionDigits: 0) } ?? "—", caption: "Measured").frame(width: 110, alignment: .leading)
            MetricColumn(value: Format.contextLength(descriptor.contextLength), caption: "Context").frame(width: 90, alignment: .leading)
            Spacer()
            HStack(spacing: 12) {
                MonoText(isDefault ? "default" : (descriptor.isAvailable ? "ready" : "unavailable"), size: 11, color: isDefault ? Theme.Colors.accent : Theme.Colors.hint)
                Menu {
                    Button("Set as default") { services.settings.defaultModelRef = .apple }.disabled(!descriptor.isAvailable || isDefault)
                } label: {
                    Text("···").font(.system(size: 15)).foregroundStyle(Theme.Colors.placeholder)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card(radius: 12, background: Theme.Colors.accentBackground, border: Theme.Colors.accentSoft)
        #else
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ModelGlyph(descriptor: descriptor, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Intelligence").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(descriptor.isAvailable ? "SYSTEM · 3B on-device" : (descriptor.unavailableReason ?? "unavailable"), size: 11, color: descriptor.isAvailable ? Theme.Colors.accent : Theme.Colors.hint)
                }
                Spacer()
                if isDefault { labelBadge("default", accent: true) }
            }
            HStack(spacing: 20) {
                MetricColumn(value: descriptor.measuredTokensPerSecond.map { Format.tokensPerSecond($0, fractionDigits: 0) } ?? "—", caption: "Speed", captionSize: 9)
                MetricColumn(value: Format.contextLength(descriptor.contextLength), caption: "Context", captionSize: 9)
                MetricColumn(value: "—", caption: "Disk", captionSize: 9)
                Spacer()
            }
        }
        .padding(16)
        .card(radius: 14, background: Theme.Colors.accentBackground, border: Theme.Colors.accentSoft)
        .contextMenu {
            Button("Set as default") { services.settings.defaultModelRef = .apple }.disabled(!descriptor.isAvailable || isDefault)
        }
        #endif
    }
}

func labelBadge(_ text: String, accent: Bool) -> some View {
    Text(text)
        .font(Theme.Fonts.mono(10))
        .foregroundStyle(accent ? Theme.Colors.accent : Theme.Colors.hint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(accent ? Theme.Colors.accentSoft : Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
}

struct InstalledModelRow: View {
    let model: InstalledModel
    let onDelete: () -> Void
    @Environment(AppServices.self) private var services

    private var descriptor: ModelDescriptor { ModelRegistry.descriptor(for: model, runtime: services.runtime) }
    private var isDefault: Bool { services.settings.defaultModelRef == model.modelRef }
    private var isLoaded: Bool { services.runtime.loadedModelID == model.id && services.runtime.loadedModel != nil }
    private var isLoading: Bool {
        if case .loading = services.runtime.state, services.runtime.loadedModelID == model.id { return true }
        return false
    }

    private var status: (String, Color) {
        if isDefault { return ("default", Theme.Colors.accent) }
        if isLoading { return ("loading", Theme.Colors.accent) }
        if isLoaded { return ("loaded", Theme.Colors.hint) }
        if !descriptor.isAvailable { return (descriptor.unavailableReason ?? "unavailable", Theme.Colors.danger) }
        return ("idle", Theme.Colors.placeholder)
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 20) {
            ModelGlyph(descriptor: descriptor, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink).lineLimit(1)
                    labelBadge("GGUF", accent: false)
                }
                Text("\(model.quantization) · \(model.source == .catalog ? "downloaded" : "imported") \(Format.shortDate(model.importedAt))")
                    .font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.hint)
            }
            .frame(width: 290, alignment: .leading)
            MetricColumn(value: Format.bytes(model.fileSizeBytes), caption: "Disk").frame(width: 110, alignment: .leading)
            MetricColumn(value: model.measuredTokensPerSecond.map { Format.tokensPerSecond($0, fractionDigits: 0) } ?? "—", caption: "Measured").frame(width: 110, alignment: .leading)
            MetricColumn(value: Format.contextLength(model.contextLength), caption: "Context").frame(width: 90, alignment: .leading)
            Spacer()
            HStack(spacing: 12) {
                MonoText(status.0, size: 11, color: status.1)
                menu
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card(radius: 12)
        .contextMenu { menuItems }
        #else
        HStack(spacing: 12) {
            ModelGlyph(descriptor: descriptor, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink).lineLimit(1)
                MonoText(subtitle, size: 11, color: descriptor.isAvailable ? Theme.Colors.hint : Theme.Colors.danger)
            }
            Spacer()
            if isDefault { labelBadge("default", accent: true) }
            menu
        }
        .padding(16)
        .card(radius: 14)
        .contextMenu { menuItems }
        #endif
    }

    private var subtitle: String {
        if let reason = descriptor.unavailableReason { return reason }
        var parts = [model.quantization, Format.bytes(model.fileSizeBytes)]
        if let tps = model.measuredTokensPerSecond { parts.append(Format.tokensPerSecond(tps, fractionDigits: 0)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Set as default") { services.settings.defaultModelRef = model.modelRef }.disabled(isDefault || !descriptor.isAvailable)
        if isLoaded {
            Button("Unload") { Task { await services.runtime.unload() } }
        } else {
            Button("Load now") { Task { _ = try? await services.runtime.model(for: model) } }.disabled(!descriptor.isAvailable || isLoading)
        }
        #if os(macOS)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([services.store.fileURL(for: model)]) }
        #endif
        Divider()
        Button("Delete \(Format.bytes(model.fileSizeBytes)) from disk…", role: .destructive, action: onDelete)
    }

    private var menu: some View {
        Menu {
            menuItems
        } label: {
            #if os(macOS)
            Text("···").font(.system(size: 15)).foregroundStyle(Theme.Colors.placeholder)
            #else
            // An ellipsis reads as "more actions"; the chevron here read as navigation, so the
            // only way to delete a model was hidden — and absent entirely on the default one.
            Image(systemName: "ellipsis.circle").font(.system(size: 17)).foregroundStyle(Theme.Colors.hint)
            #endif
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Actions for \(model.name)")
        .accessibilityIdentifier("model.actions")
    }
}

struct DownloadRow: View {
    let download: ModelDownload
    @Environment(AppServices.self) private var services

    private var live: DownloadManager.LiveProgress? { services.downloads.live[download.id] }
    private var received: Int64 { live?.received ?? download.receivedBytes }
    private var total: Int64 { max(live?.total ?? download.totalBytes, 0) }
    private var fraction: Double { total > 0 ? Double(received) / Double(total) : 0 }

    private var statusLine: String {
        switch download.state {
        case .downloading:
            var parts = ["\(Format.bytes(received)) of \(Format.bytes(total))"]
            if let live, live.bytesPerSecond > 0 { parts.append(Format.bytesPerSecond(live.bytesPerSecond)) }
            if let remaining = live?.secondsRemaining { parts.append(Format.remaining(seconds: remaining)) }
            #if os(iOS)
            if services.settings.wifiOnlyDownloads { parts.append("Wi-Fi only") }
            #endif
            return parts.joined(separator: " · ")
        case .paused:
            return "paused · \(Format.bytes(received)) of \(Format.bytes(total))"
        case .queued:
            return "waiting to start"
        case .failed:
            return download.errorMessage ?? "failed"
        case .completed:
            return "installed"
        }
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Colors.surfaceMuted)
                .frame(width: 38, height: 38)
                .overlay(Text(String(download.name.prefix(1)).uppercased()).font(Theme.Fonts.mono(12)).foregroundStyle(Theme.Colors.muted))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(download.name).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(download.state.rawValue, size: 10, color: download.state == .failed ? Theme.Colors.danger : Theme.Colors.accent)
                }
                ThinProgressBar(value: fraction).frame(maxWidth: 520)
                MonoText(statusLine, size: 11, color: download.state == .failed ? Theme.Colors.danger : Theme.Colors.hint)
            }
            Spacer()
            controls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .card(radius: 12, background: Theme.Colors.surfaceWarm)
        #else
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.surfaceMuted)
                    .frame(width: 36, height: 36)
                    .overlay(Text(String(download.name.prefix(1)).uppercased()).font(Theme.Fonts.mono(12)).foregroundStyle(Theme.Colors.muted))
                VStack(alignment: .leading, spacing: 3) {
                    Text(download.name).font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(download.state == .downloading ? "downloading" + (live?.secondsRemaining.map { " · \(Format.remaining(seconds: $0))" } ?? "") : download.state.rawValue, size: 11, color: download.state == .failed ? Theme.Colors.danger : Theme.Colors.accent)
                }
                Spacer()
                controls
            }
            ThinProgressBar(value: fraction, track: Theme.Colors.hairlinePanel)
            MonoText(statusLine, size: 11, color: download.state == .failed ? Theme.Colors.danger : Theme.Colors.hint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card(radius: 14)
        #endif
    }

    private var controls: some View {
        HStack(spacing: 8) {
            switch download.state {
            case .downloading, .queued:
                Button("Pause") { services.downloads.pause(download) }.buttonStyle(SecondaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
            case .paused:
                Button("Resume") { services.downloads.resume(download) }.buttonStyle(PrimaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
            case .failed:
                Button("Retry") { services.downloads.resume(download) }.buttonStyle(PrimaryButtonStyle(size: 12, horizontalPadding: 12, verticalPadding: 6, radius: 7))
            case .completed:
                EmptyView()
            }
            Button {
                services.downloads.cancel(download)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Colors.hint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel download")
        }
    }
}
