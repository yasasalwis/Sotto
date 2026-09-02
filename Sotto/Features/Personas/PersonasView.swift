import SwiftData
import SwiftUI
import os

struct PersonasView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]
    @State private var selectedID: UUID?

    private var selected: Persona? {
        personas.first { $0.id == selectedID } ?? personas.first
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
                    PersonaEditor(persona: selected, installed: installed)
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
            if let requested = services.state.personaToEdit {
                selectedID = requested
                services.state.personaToEdit = nil
            } else if selectedID == nil {
                selectedID = personas.first?.id
            }
        }
    }

    // MARK: - macOS list

    #if os(macOS)
    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Personas").font(Theme.Fonts.sans(19, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                Spacer()
                Button("＋ new") { createPersona() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityIdentifier("personas.new")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(personas) { persona in
                        let isSelected = persona.id == selected?.id
                        Button {
                            selectedID = persona.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(persona.name)
                                    .font(Theme.Fonts.sans(14, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? Theme.Colors.ink : Theme.Colors.textSecondary)
                                MonoText(summaryLine(persona), size: 11, color: isSelected ? Theme.Colors.accent : Theme.Colors.placeholder)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(isSelected ? Theme.Colors.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(PlainRowButtonStyle())
                        .accessibilityIdentifier("personas.row")
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Text("No personas yet").font(Theme.Fonts.sans(15, weight: .medium)).foregroundStyle(Theme.Colors.ink)
            Button("Create one") { createPersona() }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - iOS list

    #if os(iOS)
    private var iosList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(personas) { persona in
                    NavigationLink {
                        PersonaEditor(persona: persona, installed: installed)
                    } label: {
                        personaCard(persona)
                    }
                    .buttonStyle(PlainRowButtonStyle())
                    .accessibilityIdentifier("personas.row")
                }
            }
            .padding(16)
        }
        .background(Theme.Colors.panel)
        .navigationTitle("Personas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Theme.Colors.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createPersona() } label: { Image(systemName: "plus").foregroundStyle(Theme.Colors.accent) }
                    .accessibilityLabel("New persona")
            }
        }
    }

    private func personaCard(_ persona: Persona) -> some View {
        let isDefault = services.settings.defaultPersonaID == persona.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(persona.name).font(Theme.Fonts.sans(16, weight: .medium)).foregroundStyle(Theme.Colors.ink)
                if isDefault { labelBadge("default", accent: true) }
                Spacer()
                MonoText("\(persona.usageCount) chats", size: 10)
            }
            Text(persona.summary)
                .font(Theme.Fonts.sans(13))
                .lineSpacing(4)
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                tag(modelLabel(persona), accent: false)
                tag("temp \(String(format: "%.1f", persona.temperature))", accent: false)
                if persona.localOnly { tag("local only", accent: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(radius: 14, border: isDefault ? Theme.Colors.accent : Theme.Colors.border, lineWidth: isDefault ? 1.5 : 1)
    }

    private func tag(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(Theme.Fonts.mono(10))
            .foregroundStyle(accent ? Theme.Colors.accent : Theme.Colors.hint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent ? Theme.Colors.accentPale : Theme.Colors.sidebar, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    #endif

    // MARK: - Shared

    private func modelLabel(_ persona: Persona) -> String {
        guard let ref = persona.modelRef else { return "any model" }
        return ModelRegistry.descriptor(for: ref, installed: installed, runtime: services.runtime)?.shortLabel ?? "model removed"
    }

    private func summaryLine(_ persona: Persona) -> String {
        "\(modelLabel(persona)) · temp \(String(format: "%.1f", persona.temperature))"
    }

    private func createPersona() {
        let persona = Persona(name: "New persona", summary: "Describe what this persona is for.", systemPrompt: "", sortOrder: (personas.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(persona)
        try? context.save()
        selectedID = persona.id
        #if os(iOS)
        services.state.personaToEdit = persona.id
        #endif
    }
}

/// Edits one persona. Changes are staged locally and written on Save.
struct PersonaEditor: View {
    let persona: Persona
    let installed: [InstalledModel]
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""
    @State private var systemPrompt = ""
    @State private var modelRef: ModelRef?
    @State private var temperature = 0.7
    @State private var maxTokens = 1024
    @State private var localOnly = false
    @State private var shortcutSlot: Int?
    @State private var confirmDelete = false
    @State private var saved = false

    private var isDirty: Bool {
        name != persona.name || summary != persona.summary || systemPrompt != persona.systemPrompt || modelRef != persona.modelRef || temperature != persona.temperature || maxTokens != persona.maxTokens || localOnly != persona.localOnly || shortcutSlot != persona.shortcutSlot
    }

    private var modelName: String {
        guard let modelRef else { return "Conversation's model" }
        return ModelRegistry.descriptor(for: modelRef, installed: installed, runtime: services.runtime)?.name ?? "Model removed"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Summary")
                    TextField("One line shown in lists", text: $summary)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.sans(14))
                        .foregroundStyle(Theme.Colors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                        .onChange(of: summary) { _, value in if value.count > 160 { summary = String(value.prefix(160)) } }
                }
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("System prompt")
                    TextEditor(text: $systemPrompt)
                        .font(Theme.Fonts.sans(14))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.Colors.text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                        .onChange(of: systemPrompt) { _, value in if value.count > Persona.maximumPromptLength { systemPrompt = String(value.prefix(Persona.maximumPromptLength)) } }
                        .accessibilityIdentifier("persona.prompt")
                    MonoText("\(Format.integer(systemPrompt.count)) / \(Format.integer(Persona.maximumPromptLength)) characters", size: 10, color: Theme.Colors.faint)
                }
                cards
                localOnlyRow
                HStack {
                    Button("Delete persona…") { confirmDelete = true }
                        .buttonStyle(SecondaryButtonStyle(foreground: Theme.Colors.danger, border: Theme.Colors.dangerBorder))
                    Spacer()
                    if saved { MonoText("saved", size: 11, color: Theme.Colors.accent) }
                }
            }
            .padding(.horizontal, editorPadding)
            .padding(.vertical, 34)
        }
        .background(Theme.Colors.surface)
        .onAppear(perform: load)
        .confirmationDialog("Delete \(persona.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
        #if os(iOS)
        .navigationTitle(persona.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.disabled(!isDirty).foregroundStyle(Theme.Colors.accent)
            }
        }
        #endif
    }

    private var editorPadding: CGFloat {
        #if os(macOS)
        return Theme.Spacing.page
        #else
        return 16
        #endif
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                TextField("Persona name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sans(26, weight: .medium))
                    .foregroundStyle(Theme.Colors.ink)
                    .onChange(of: name) { _, value in if value.count > Persona.maximumNameLength { name = String(value.prefix(Persona.maximumNameLength)) } }
                    .accessibilityIdentifier("persona.name")
                MonoText("used in \(persona.usageCount) conversation\(persona.usageCount == 1 ? "" : "s")" + (shortcutSlot.map { " · ⌥⌘\($0)" } ?? ""), size: 12)
            }
            Spacer()
            #if os(macOS)
            HStack(spacing: 10) {
                Button("Duplicate") { duplicate() }.buttonStyle(SecondaryButtonStyle())
                Button("Save") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(!isDirty).accessibilityIdentifier("persona.save")
            }
            #endif
        }
    }

    private var cards: some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Model")
                Menu {
                    Button("Use the conversation's model") { modelRef = nil }
                    Divider()
                    ForEach(ModelRegistry.all(installed: installed, runtime: services.runtime)) { descriptor in
                        Button(descriptor.name) { modelRef = descriptor.ref }
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot()
                        Text(modelName).font(Theme.Fonts.sans(14)).foregroundStyle(Theme.Colors.ink)
                        Spacer()
                        Text("▾").font(.system(size: 9)).foregroundStyle(Theme.Colors.placeholder)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                Text("Falls back to Apple Intelligence if unloaded")
                    .font(Theme.Fonts.sans(12)).foregroundStyle(Theme.Colors.hint)
                SectionLabel("Shortcut").padding(.top, 6)
                Picker("Shortcut", selection: $shortcutSlot) {
                    Text("None").tag(Int?.none)
                    ForEach(1...9, id: \.self) { slot in
                        Text("⌥⌘\(slot)").tag(Int?.some(slot))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card(radius: Theme.Radius.card)

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Sampling")
                SamplingSlider(label: "Temperature", value: String(format: "%.1f", temperature), fraction: temperature / Persona.temperatureRange.upperBound) { fraction in
                    temperature = (fraction * Persona.temperatureRange.upperBound * 10).rounded() / 10
                }
                SamplingSlider(label: "Max tokens", value: Format.integer(maxTokens), fraction: Double(maxTokens) / Double(Persona.maxTokensRange.upperBound)) { fraction in
                    maxTokens = max(Persona.maxTokensRange.lowerBound, (Int(fraction * Double(Persona.maxTokensRange.upperBound)) / 64) * 64)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card(radius: Theme.Radius.card)
        }
    }

    private var localOnlyRow: some View {
        HStack(spacing: 10) {
            MonoText("LOCAL ONLY", size: 11, color: Theme.Colors.accent)
            Text("This persona will never route to Private Cloud Compute.")
                .font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Toggle("", isOn: $localOnly).toggleStyle(SottoToggleStyle(compact: true)).labelsHidden()
                .accessibilityLabel("Local only")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card(radius: Theme.Radius.card, background: Theme.Colors.accentBackground, border: Theme.Colors.accentSoft)
    }

    private func load() {
        name = persona.name
        summary = persona.summary
        systemPrompt = persona.systemPrompt
        modelRef = persona.modelRef
        temperature = persona.temperature
        maxTokens = persona.maxTokens
        localOnly = persona.localOnly
        shortcutSlot = persona.shortcutSlot
    }

    private func save() {
        persona.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled persona" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        persona.summary = summary
        persona.systemPrompt = systemPrompt
        persona.modelRef = modelRef
        persona.temperature = temperature
        persona.maxTokens = maxTokens
        persona.localOnly = localOnly
        persona.updatedAt = .now
        if let slot = shortcutSlot, let others = try? context.fetch(FetchDescriptor<Persona>()) {
            for other in others where other.id != persona.id && other.shortcutSlot == slot {
                other.shortcutSlot = nil
            }
        }
        persona.shortcutSlot = shortcutSlot
        do {
            try context.save()
            saved = true
            Log.app.info("Saved persona")
        } catch {
            services.state.showError("Couldn't save", error.localizedDescription)
        }
        #if os(iOS)
        dismiss()
        #endif
    }

    private func duplicate() {
        let copy = Persona(
            name: "\(persona.name) copy",
            summary: persona.summary,
            systemPrompt: persona.systemPrompt,
            modelRef: persona.modelRef,
            temperature: persona.temperature,
            topP: persona.topP,
            maxTokens: persona.maxTokens,
            localOnly: persona.localOnly,
            sortOrder: persona.sortOrder + 1
        )
        context.insert(copy)
        try? context.save()
        services.state.personaToEdit = copy.id
    }

    private func delete() {
        if services.settings.defaultPersonaID == persona.id {
            services.settings.defaultPersonaID = nil
        }
        context.delete(persona)
        try? context.save()
        dismiss()
    }
}
