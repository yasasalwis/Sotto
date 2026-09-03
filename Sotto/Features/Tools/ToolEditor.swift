import os
import SwiftData
import SwiftUI

/// Edits one tool. Built-in tools expose only description, approval and the enable switch;
/// everything else is fixed because their behaviour lives in code.
struct ToolEditor: View {
    let tool: ToolDefinition
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var name = ""
    @State private var summary = ""
    @State private var kind: ToolKind = .httpRequest
    @State private var parameters: [ToolParameter] = []
    @State private var approval: ToolApprovalMode = .askEveryTime
    @State private var isEnabled = true
    @State private var http = HTTPToolConfig()
    @State private var shell = ShellToolConfig()
    @State private var search = WebSearchConfig()
    @State private var apiKey = ""
    @State private var originalAPIKey = ""
    @State private var headerText = ""
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var testValues: [String: String] = [:]
    @State private var testOutput: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    private var nameError: String? {
        if name.isEmpty { return "Give the tool a name the model can call." }
        if !ToolDefinition.isValidName(name) { return "Use 2–41 characters: lowercase letters, digits and underscores, starting with a letter." }
        if siblingNames.contains(name) { return "Another tool already answers to “\(name)”." }
        return nil
    }

    /// Names taken by other tools; a model could not tell two tools with the same name apart.
    private var siblingNames: Set<String> {
        let descriptor = FetchDescriptor<ToolDefinition>()
        let others = (try? context.fetch(descriptor)) ?? []
        return Set(others.filter { $0.id != tool.id }.map(\.name))
    }

    private var isDirty: Bool {
        displayName != tool.displayName || name != tool.name || summary != tool.summary
            || kind != tool.kind || parameters != tool.parameters || approval != tool.approval
            || isEnabled != tool.isEnabled
            || (kind == .httpRequest && http != (tool.httpConfig ?? HTTPToolConfig()))
            || (kind == .shellCommand && shell != (tool.shellConfig ?? ShellToolConfig()))
            || (kind == .webSearch && (search != (tool.webSearchConfig ?? WebSearchConfig()) || apiKey != originalAPIKey))
    }

    private var canSave: Bool { nameError == nil && !summary.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                identitySection
                if !tool.isBuiltIn {
                    kindSection
                    parametersSection
                }
                if tool.kind != .builtIn {
                    configSection
                }
                behaviourSection
                testSection
                if !tool.isBuiltIn {
                    HStack {
                        Button("Delete tool…") { confirmDelete = true }
                            .buttonStyle(SecondaryButtonStyle(foreground: Theme.Colors.danger, border: Theme.Colors.dangerBorder))
                        Spacer()
                        if saved { MonoText("saved", size: 11, color: Theme.Colors.accent) }
                    }
                } else if saved {
                    MonoText("saved", size: 11, color: Theme.Colors.accent)
                }
            }
            .padding(.horizontal, editorPadding)
            .padding(.vertical, 34)
        }
        .background(Theme.Colors.surface)
        .onAppear(perform: load)
        .confirmationDialog("Delete \(tool.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Conversations that already used this tool keep their record of what it returned.")
        }
        #if os(iOS)
        .navigationTitle(tool.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.disabled(!isDirty || !canSave).foregroundStyle(Theme.Colors.accent)
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

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolGlyph(kind: kind, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Tool name", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sans(24, weight: .medium))
                    .foregroundStyle(Theme.Colors.ink)
                    .disabled(tool.isBuiltIn)
                    .onChange(of: displayName) { _, value in
                        if value.count > 48 { displayName = String(value.prefix(48)) }
                        if !tool.isBuiltIn, name == ToolDefinition.suggestedName(from: String(value.dropLast())) || name == "my_tool" {
                            name = ToolDefinition.suggestedName(from: displayName)
                        }
                    }
                    .accessibilityIdentifier("tool.displayName")
                MonoText(tool.isBuiltIn && tool.kind == .builtIn ? "built in · runs on this device" : kind.explanation, size: 11)
            }
            Spacer()
            #if os(macOS)
            HStack(spacing: 10) {
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(SottoToggleStyle(compact: true))
                    .labelsHidden()
                    .disabled(!kind.isAvailableOnThisPlatform)
                    .accessibilityLabel("Enabled")
                Button("Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isDirty || !canSave)
                    .accessibilityIdentifier("tool.save")
            }
            #endif
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("What the model sees")
            TextEditor(text: $summary)
                .font(Theme.Fonts.sans(14))
                .lineSpacing(5)
                .foregroundStyle(Theme.Colors.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                .onChange(of: summary) { _, value in
                    if value.count > ToolDefinition.maximumSummaryLength {
                        summary = String(value.prefix(ToolDefinition.maximumSummaryLength))
                    }
                }
                .accessibilityIdentifier("tool.summary")
            HStack {
                MonoText("\(summary.count) / \(ToolDefinition.maximumSummaryLength)", size: 10, color: Theme.Colors.faint)
                Spacer()
                MonoText("function name", size: 10, color: Theme.Colors.faint)
                TextField("my_tool", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(nameError == nil ? Theme.Colors.ink : Theme.Colors.danger)
                    .frame(width: 180)
                    .disabled(tool.isBuiltIn)
                    .onChange(of: name) { _, value in
                        let cleaned = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if cleaned != value { name = cleaned }
                        if name.count > 41 { name = String(name.prefix(41)) }
                    }
                    .accessibilityIdentifier("tool.name")
            }
            if let nameError, !tool.isBuiltIn {
                Text(nameError).font(Theme.Fonts.sans(12)).foregroundStyle(Theme.Colors.danger)
            }
        }
    }

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Kind")
            kindCards
        }
    }

    @ViewBuilder
    private var kindCards: some View {
        let kinds = ToolKind.creatableKinds
        #if os(macOS)
        HStack(alignment: .top, spacing: 10) {
            ForEach(kinds) { kindCard($0) }
        }
        #else
        VStack(spacing: 8) {
            ForEach(kinds) { kindCard($0) }
        }
        #endif
    }

    private func kindCard(_ candidate: ToolKind) -> some View {
        Button {
            kind = candidate
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ToolGlyph(kind: candidate, size: 22)
                    Text(candidate.label)
                        .font(Theme.Fonts.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                Text(candidate.explanation)
                    .font(Theme.Fonts.sans(12))
                    .foregroundStyle(Theme.Colors.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card(
                radius: Theme.Radius.card,
                background: kind == candidate ? Theme.Colors.accentBackground : Theme.Colors.surface,
                border: kind == candidate ? Theme.Colors.accent : Theme.Colors.border,
                lineWidth: kind == candidate ? 1.5 : 1
            )
        }
        .buttonStyle(PlainRowButtonStyle())
        .disabled(!candidate.isAvailableOnThisPlatform)
        .opacity(candidate.isAvailableOnThisPlatform ? 1 : 0.5)
    }

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel("Parameters")
                Spacer()
                Button("＋ add") {
                    guard parameters.count < ToolDefinition.maximumParameters else { return }
                    parameters.append(ToolParameter(name: "value\(parameters.count + 1)", summary: ""))
                }
                .buttonStyle(.plain)
                .font(Theme.Fonts.mono(11))
                .foregroundStyle(parameters.count < ToolDefinition.maximumParameters ? Theme.Colors.accent : Theme.Colors.placeholder)
                .disabled(parameters.count >= ToolDefinition.maximumParameters)
                .accessibilityIdentifier("tool.addParameter")
            }
            if parameters.isEmpty {
                Text("No parameters. The model calls this tool with no arguments.")
                    .font(Theme.Fonts.sans(13))
                    .foregroundStyle(Theme.Colors.hint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .card(radius: Theme.Radius.card)
            } else {
                VStack(spacing: 8) {
                    ForEach($parameters) { $parameter in
                        parameterRow($parameter)
                    }
                }
                Text("Use {name} in the address, body or command below to insert an argument. Values are escaped for you.")
                    .font(Theme.Fonts.sans(12))
                    .foregroundStyle(Theme.Colors.faint)
            }
        }
    }

    private func parameterRow(_ parameter: Binding<ToolParameter>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("name", text: parameter.name)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(width: 130)
                    .onChange(of: parameter.wrappedValue.name) { _, value in
                        let cleaned = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if cleaned != value { parameter.wrappedValue.name = cleaned }
                    }
                Picker("", selection: parameter.type) {
                    ForEach(ToolParameterType.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
                .frame(width: 110)
                Button {
                    parameter.wrappedValue.isRequired.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: parameter.wrappedValue.isRequired ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(parameter.wrappedValue.isRequired ? Theme.Colors.accent : Theme.Colors.borderStrong)
                        Text("required").font(Theme.Fonts.sans(12)).foregroundStyle(Theme.Colors.muted)
                    }
                }
                .buttonStyle(PlainRowButtonStyle())
                Spacer()
                Button {
                    parameters.removeAll { $0.id == parameter.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle").font(.system(size: 13)).foregroundStyle(Theme.Colors.hint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove parameter")
            }
            TextField("What this value means, in the model's words", text: parameter.summary)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.sans(13))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(14)
        .card(radius: Theme.Radius.card)
    }

    @ViewBuilder
    private var configSection: some View {
        switch kind {
        case .httpRequest:
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Request")
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("", selection: $http.method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.accent)
                        .frame(width: 96)
                        TextField("https://example.com/api?q={query}", text: $http.urlTemplate)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.Colors.ink)
                            .accessibilityIdentifier("tool.url")
                    }
                    if http.method == "POST" {
                        TextField("Request body, e.g. {\"q\": \"{query}\"}", text: $http.bodyTemplate, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.Colors.ink)
                            .lineLimit(1...4)
                    }
                    TextField("Header lines, e.g. Authorization: Bearer …", text: $headerText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.mono(12))
                        .foregroundStyle(Theme.Colors.ink)
                        .lineLimit(1...4)
                    TextField("Path into the JSON answer, e.g. current.temperature (blank returns everything)", text: $http.responsePath)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.mono(12))
                        .foregroundStyle(Theme.Colors.ink)
                }
                .padding(16)
                .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                Text("Only https addresses are allowed. Whatever the model puts in the arguments is sent to that server, so use tools you trust.")
                    .font(Theme.Fonts.sans(12))
                    .foregroundStyle(Theme.Colors.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .shellCommand:
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Command")
                TextField("date +%V", text: $shell.command, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1...6)
                    .padding(16)
                    .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                    .disabled(!ToolKind.shellCommand.isAvailableOnThisPlatform)
                    .accessibilityIdentifier("tool.command")
                // A shell tool can survive in the database after an update to a build that has
                // no shell tool, so the editor says what will actually happen rather than
                // describing a run that cannot occur.
                if ToolKind.shellCommand.isAvailableOnThisPlatform {
                    Text("Runs with /bin/zsh as you, from your home folder, with a \(Int(ToolExecutor.timeout)) second limit. Arguments are quoted before they are inserted, so they cannot add commands of their own.")
                        .font(Theme.Fonts.sans(12))
                        .foregroundStyle(Theme.Colors.faint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This build of Sotto cannot run shell tools, so this one will not run. You can delete it.")
                        .font(Theme.Fonts.sans(12))
                        .foregroundStyle(Theme.Colors.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .webSearch:
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Google credentials")
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        MonoText("API key", size: 12, color: Theme.Colors.muted).frame(width: 120, alignment: .leading)
                        SecureField("AIza…", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.Colors.ink)
                            .accessibilityIdentifier("tool.apiKey")
                    }
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                    HStack(spacing: 10) {
                        MonoText("engine id (cx)", size: 12, color: Theme.Colors.muted).frame(width: 120, alignment: .leading)
                        TextField("a1b2c3d4e5f6g7h8i", text: $search.searchEngineID)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.Colors.ink)
                            .accessibilityIdentifier("tool.engineID")
                    }
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                    HStack(spacing: 10) {
                        MonoText("results", size: 12, color: Theme.Colors.muted).frame(width: 120, alignment: .leading)
                        Picker("", selection: $search.resultCount) {
                            ForEach(Array(WebSearchConfig.resultCountRange), id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.accent)
                        Spacer()
                        Text("SafeSearch").font(Theme.Fonts.sans(13)).foregroundStyle(Theme.Colors.muted).fixedSize()
                        Toggle("", isOn: $search.safeSearch)
                            .toggleStyle(SottoToggleStyle(compact: true))
                            .labelsHidden()
                            .accessibilityLabel("SafeSearch")
                    }
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                    HStack(spacing: 10) {
                        MonoText("limit to site", size: 12, color: Theme.Colors.muted).frame(width: 120, alignment: .leading)
                        TextField("optional, e.g. apple.com", text: $search.site)
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.Colors.ink)
                    }
                }
                .padding(16)
                .card(radius: Theme.Radius.card, border: Theme.Colors.borderMedium)
                VStack(alignment: .leading, spacing: 6) {
                    Text("The key is kept in your keychain, not in Sotto's database, and never appears in an export. Only the words the model searches for are sent to Google.")
                        .font(Theme.Fonts.sans(12))
                        .foregroundStyle(Theme.Colors.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Link("Create a search engine", destination: URL(string: WebSearchTool.setupURL)!)
                        Link("Get an API key", destination: URL(string: WebSearchTool.keyURL)!)
                    }
                    .font(Theme.Fonts.sans(12))
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        case .builtIn:
            EmptyView()
        }
    }

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Before it runs")
            VStack(spacing: 0) {
                ForEach(ToolApprovalMode.allCases) { mode in
                    Button {
                        approval = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: approval == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(approval == mode ? Theme.Colors.accent : Theme.Colors.borderStrong)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label).font(Theme.Fonts.sans(14)).foregroundStyle(Theme.Colors.ink)
                                Text(mode == .askEveryTime
                                     ? "Sotto shows the call and waits for you."
                                     : "The call runs as soon as the model asks.")
                                    .font(Theme.Fonts.sans(12))
                                    .foregroundStyle(Theme.Colors.hint)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            if mode == .askEveryTime { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
                        }
                    }
                    .buttonStyle(PlainRowButtonStyle())
                }
            }
            .card(radius: Theme.Radius.card)
            #if os(iOS)
            HStack {
                Text("Enabled").font(Theme.Fonts.sans(14)).foregroundStyle(Theme.Colors.ink)
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(SottoToggleStyle(compact: true))
                    .labelsHidden()
                    .disabled(!kind.isAvailableOnThisPlatform)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .card(radius: Theme.Radius.card)
            #endif
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Try it")
            VStack(spacing: 10) {
                ForEach(parameters) { parameter in
                    HStack(spacing: 10) {
                        MonoText(parameter.name, size: 12, color: Theme.Colors.muted).frame(width: 120, alignment: .leading)
                        TextField(parameter.summary.isEmpty ? "value" : parameter.summary, text: testBinding(parameter.name))
                            .textFieldStyle(.plain)
                            .font(Theme.Fonts.sans(13))
                            .foregroundStyle(Theme.Colors.ink)
                    }
                }
                HStack(spacing: 10) {
                    Button(isTesting ? "Running…" : "Run once") { runTest() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isTesting)
                        .accessibilityIdentifier("tool.test")
                    if testOutput != nil {
                        MonoText(testSucceeded ? "ok" : "failed", size: 11, color: testSucceeded ? Theme.Colors.accent : Theme.Colors.danger)
                    }
                    Spacer()
                    Text("Runs the tool now, with no model involved.")
                        .font(Theme.Fonts.sans(12))
                        .foregroundStyle(Theme.Colors.faint)
                }
                if let testOutput {
                    ScrollView {
                        Text(testOutput)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(testSucceeded ? Theme.Colors.text : Theme.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                    .padding(12)
                    .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(16)
            .card(radius: Theme.Radius.card)
        }
    }

    // MARK: - Actions

    private func testBinding(_ key: String) -> Binding<String> {
        Binding(get: { testValues[key] ?? "" }, set: { testValues[key] = $0 })
    }

    private func load() {
        displayName = tool.displayName
        name = tool.name
        summary = tool.summary
        kind = tool.kind
        parameters = tool.parameters
        approval = tool.approval
        isEnabled = tool.isEnabled
        http = tool.httpConfig ?? HTTPToolConfig()
        shell = tool.shellConfig ?? ShellToolConfig()
        search = tool.webSearchConfig ?? WebSearchConfig()
        apiKey = tool.apiKey ?? ""
        originalAPIKey = apiKey
        headerText = http.headers.keys.sorted().map { "\($0): \(http.headers[$0] ?? "")" }.joined(separator: "\n")
    }

    private func save() {
        guard canSave else { return }
        if !tool.isBuiltIn {
            tool.displayName = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled tool" : displayName.trimmingCharacters(in: .whitespaces)
            tool.name = name
            tool.kind = kind
            tool.parameters = parameters.filter { ToolDefinition.isValidName($0.name) }
        }
        if tool.kind != .builtIn {
            switch kind {
            case .httpRequest:
                http.headers = Self.parseHeaders(headerText)
                tool.httpConfig = http
            case .shellCommand:
                tool.shellConfig = shell
            case .webSearch:
                search.searchEngineID = search.searchEngineID.trimmingCharacters(in: .whitespaces)
                search.site = search.site.trimmingCharacters(in: .whitespaces)
                tool.webSearchConfig = search
                if apiKey != originalAPIKey {
                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        KeychainStore.remove(tool.secretAccount)
                    } else if !KeychainStore.set(apiKey, for: tool.secretAccount) {
                        services.state.showError("Couldn't save the key", "The keychain refused to store this API key. The rest of the tool was saved.")
                    }
                    originalAPIKey = apiKey
                }
            case .builtIn:
                break
            }
        }
        tool.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        tool.approval = approval
        tool.isEnabled = isEnabled && kind.isAvailableOnThisPlatform
        tool.updatedAt = .now
        do {
            try context.save()
            saved = true
            Log.app.info("Saved tool \(tool.name, privacy: .public)")
        } catch {
            services.state.showError("Couldn't save", error.localizedDescription)
        }
        #if os(iOS)
        dismiss()
        #endif
    }

    private func runTest() {
        isTesting = true
        testOutput = nil
        var arguments: [String: Any] = [:]
        for parameter in parameters {
            let raw = testValues[parameter.name] ?? ""
            guard !raw.isEmpty else { continue }
            switch parameter.type {
            case .string: arguments[parameter.name] = raw
            case .number: arguments[parameter.name] = Double(raw) ?? raw
            case .boolean: arguments[parameter.name] = (raw as NSString).boolValue
            }
        }
        // Test against what is on screen, not what was last saved.
        let draft = ToolDefinition(
            name: name.isEmpty ? tool.name : name,
            displayName: displayName,
            summary: summary,
            kind: kind,
            parameters: parameters,
            approval: approval,
            isBuiltIn: tool.isBuiltIn,
            builtIn: tool.builtIn
        )
        switch kind {
        case .httpRequest:
            var config = http
            config.headers = Self.parseHeaders(headerText)
            draft.httpConfig = config
        case .shellCommand:
            draft.shellConfig = shell
        case .webSearch:
            draft.webSearchConfig = search
        case .builtIn:
            break
        }
        let executor = ToolExecutor(settings: services.settings, context: context)
        let pendingKey = apiKey
        Task {
            if kind == .webSearch {
                // Try what is on screen without committing it to the keychain yet.
                let key = pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !search.searchEngineID.trimmingCharacters(in: .whitespaces).isEmpty else {
                    testSucceeded = false
                    testOutput = "Add an API key and a search engine id first."
                    isTesting = false
                    return
                }
                do {
                    let (text, _) = try await WebSearchTool.run(search, apiKey: key, arguments: arguments, settings: services.settings)
                    testSucceeded = true
                    testOutput = text
                } catch {
                    testSucceeded = false
                    testOutput = error.localizedDescription
                }
                isTesting = false
                return
            }
            let result = await executor.execute(draft, arguments: arguments)
            testSucceeded = result.success
            testOutput = result.text
            isTesting = false
        }
    }

    private func delete() {
        KeychainStore.remove(tool.secretAccount)
        context.delete(tool)
        try? context.save()
        dismiss()
    }

    /// Parses "Name: value" lines into headers, ignoring blanks and malformed lines.
    static func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            headers[key] = value
        }
        return headers
    }
}
