import os
import SwiftData
import SwiftUI

struct ToolsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ToolDefinition.sortOrder), SortDescriptor(\ToolDefinition.createdAt)])
    private var tools: [ToolDefinition]
    @State private var selectedID: UUID?
    @State private var editing: ToolDefinition?

    private var selected: ToolDefinition? {
        tools.first { $0.id == selectedID } ?? tools.first
    }

    var body: some View {
        Group {
            #if os(macOS)
            HStack(spacing: 0) {
                list
                    .frame(width: 330)
                    .background(Theme.Colors.panel)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.Colors.hairlinePanel).frame(width: 1) }
                if let selected {
                    ToolEditor(tool: selected)
                        .id(selected.id)
                } else {
                    emptyEditor
                }
            }
            #else
            iosList
            #endif
        }
        .background(Theme.Colors.surface)
        .onAppear {
            if let requested = services.state.toolToEdit {
                selectedID = requested
                services.state.toolToEdit = nil
            } else if selectedID == nil {
                selectedID = tools.first?.id
            }
        }
    }

    // MARK: - macOS

    #if os(macOS)
    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tools").font(Theme.Fonts.sans(19, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(summaryLine, size: 11)
                }
                Spacer()
                Button {
                    createTool()
                } label: {
                    Text("＋ new")
                        .font(Theme.Fonts.mono(11))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainRowButtonStyle())
                .accessibilityIdentifier("tools.new")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tools) { tool in
                        row(tool)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            masterSwitch
        }
    }

    private func row(_ tool: ToolDefinition) -> some View {
        let isSelected = tool.id == selected?.id
        return Button {
            selectedID = tool.id
        } label: {
            HStack(spacing: 11) {
                ToolGlyph(kind: tool.kind, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.displayName)
                        .font(Theme.Fonts.sans(14, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(tool.isUsable ? (isSelected ? Theme.Colors.ink : Theme.Colors.textSecondary) : Theme.Colors.placeholder)
                        .lineLimit(1)
                    // The name alone; "needs setup" is carried by the red tint and the editor.
                    MonoText(tool.name,
                             size: 11,
                             color: tool.needsSetup ? Theme.Colors.danger : (isSelected ? Theme.Colors.accent : Theme.Colors.placeholder))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(tool.needsSetup ? "This tool needs setup before a model can use it" : tool.name)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: enabledBinding(tool))
                    .toggleStyle(SottoToggleStyle(compact: true))
                    .labelsHidden()
                    .disabled(!tool.kind.isAvailableOnThisPlatform)
                    .accessibilityLabel("Enable \(tool.displayName)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isSelected ? Theme.Colors.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("tools.row")
    }

    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Text("No tools yet").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
            Button("Create one") { createTool() }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iosList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(tools) { tool in
                    NavigationLink {
                        ToolEditor(tool: tool)
                    } label: {
                        card(tool)
                    }
                    .buttonStyle(PlainRowButtonStyle())
                    .accessibilityIdentifier("tools.row")
                }
                masterSwitch
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Theme.Colors.panel)
        .navigationDestination(item: $editing) { tool in
            ToolEditor(tool: tool)
        }
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Theme.Colors.textSecondary)
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Tools").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(summaryLine, size: 10)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createTool() } label: { Image(systemName: "plus").foregroundStyle(Theme.Colors.accent) }
                    .accessibilityIdentifier("tools.new")
            }
        }
    }

    private func card(_ tool: ToolDefinition) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ToolGlyph(kind: tool.kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName).font(Theme.Fonts.sans(16, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                    MonoText(tool.name, size: 11)
                }
                Spacer()
                Toggle("", isOn: enabledBinding(tool))
                    .toggleStyle(SottoToggleStyle(compact: true))
                    .labelsHidden()
                    .disabled(!tool.kind.isAvailableOnThisPlatform)
                    .accessibilityLabel("Enable \(tool.displayName)")
            }
            Text(tool.summary)
                .font(Theme.Fonts.sans(13))
                .lineSpacing(4)
                .foregroundStyle(Theme.Colors.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            ToolBadges(tool: tool)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(radius: 14)
        .opacity(tool.kind.isAvailableOnThisPlatform ? 1 : 0.55)
    }
    #endif

    // MARK: - Shared

    private var summaryLine: String {
        let enabled = tools.filter(\.isUsable).count
        return services.settings.toolsEnabled ? "\(enabled) of \(tools.count) enabled" : "tools are off"
    }

    private var masterSwitch: some View {
        @Bindable var settings = services.settings
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tool calling")
                    .font(Theme.Fonts.sans(14, weight: .medium))
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize()
                Text("Off hides every tool from every model.")
                    .font(Theme.Fonts.sans(12))
                    .foregroundStyle(Theme.Colors.hint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $settings.toolsEnabled)
                .toggleStyle(SottoToggleStyle(compact: true))
                .labelsHidden()
                .accessibilityLabel("Let models call tools")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(radius: 12, background: Theme.Colors.surface)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func enabledBinding(_ tool: ToolDefinition) -> Binding<Bool> {
        Binding(
            get: { tool.isEnabled },
            set: { newValue in
                tool.isEnabled = newValue
                tool.updatedAt = .now
                try? context.save()
            }
        )
    }

    private func createTool() {
        let tool = ToolDefinition(
            name: Self.unusedName(among: tools),
            displayName: "New tool",
            summary: "Describe when the model should call this tool and what it returns.",
            kind: .httpRequest,
            parameters: [],
            approval: .askEveryTime,
            isEnabled: false,
            sortOrder: (tools.map(\.sortOrder).max() ?? 0) + 1
        )
        tool.httpConfig = HTTPToolConfig()
        context.insert(tool)
        do {
            try context.save()
        } catch {
            context.delete(tool)
            services.state.showError("Couldn't create the tool", error.localizedDescription)
            return
        }
        selectedID = tool.id
        #if os(iOS)
        editing = tool
        #endif
    }

    /// Two tools may not share a function name, so the new one gets the first free suffix.
    static func unusedName(among tools: [ToolDefinition]) -> String {
        let taken = Set(tools.map(\.name))
        guard taken.contains("my_tool") else { return "my_tool" }
        for index in 2...99 where !taken.contains("my_tool_\(index)") {
            return "my_tool_\(index)"
        }
        return "my_tool_\(UUID().uuidString.prefix(4).lowercased())"
    }
}

struct ToolGlyph: View {
    let kind: ToolKind
    var size: CGFloat = 30

    private var symbol: String {
        switch kind {
        case .builtIn: return "wrench.adjustable"
        case .webSearch: return "magnifyingglass"
        case .httpRequest: return "globe"
        case .shellCommand: return "terminal"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(kind == .builtIn ? Theme.Colors.accentSoft : Theme.Colors.surfaceMuted)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(kind == .builtIn ? Theme.Colors.accent : Theme.Colors.muted)
            }
            .accessibilityHidden(true)
    }
}

struct ToolBadges: View {
    let tool: ToolDefinition

    var body: some View {
        HStack(spacing: 8) {
            labelBadge(tool.kind.label.lowercased(), accent: tool.kind == .builtIn)
            if tool.approval == .automatic {
                labelBadge("automatic", accent: false)
            } else {
                labelBadge("asks first", accent: true)
            }
            if tool.usesNetwork { labelBadge("network", accent: false) }
            if tool.needsSetup { labelBadge("needs setup", accent: true) }
            if let reason = tool.kind.unavailableReason { labelBadge(reason, accent: false) }
            Spacer()
            if tool.usageCount > 0 {
                MonoText("\(tool.usageCount) call\(tool.usageCount == 1 ? "" : "s")", size: 10, color: Theme.Colors.faint)
            }
        }
    }
}
