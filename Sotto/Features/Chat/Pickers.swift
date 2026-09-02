import SwiftData
import SwiftUI

/// iOS bottom sheet for choosing the model of the current chat.
struct ModelPickerSheet: View {
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InstalledModel.importedAt, order: .reverse) private var installed: [InstalledModel]

    private var descriptors: [ModelDescriptor] {
        ModelRegistry.all(installed: installed, runtime: services.runtime)
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Theme.Colors.borderStrong).frame(width: 38, height: 4).padding(.top, 12)
            HStack(alignment: .firstTextBaseline) {
                Text("Model")
                    .font(Theme.Fonts.sans(21, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
                MonoText("this chat only", size: 11)
            }
            .padding(.horizontal, 22)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(descriptors) { descriptor in
                        ModelChoiceCard(descriptor: descriptor, selected: descriptor.ref == session.conversation.modelRef) {
                            session.setModel(descriptor.ref)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 14)
                HairlineRule(color: Theme.Colors.hairlineSoft).padding(.horizontal, 22).padding(.vertical, 8)
                Button("Compare two models…") {
                    services.state.comparePrompt = session.draft
                    services.state.compareModelRefs = [session.conversation.modelRef]
                    dismiss()
                    services.state.sheet = .compare
                }
                .buttonStyle(SecondaryButtonStyle(size: 15, horizontalPadding: 14, verticalPadding: 14, radius: 13, fullWidth: true))
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
        }
        .background(Theme.Colors.surface)
    }
}

struct ModelChoiceCard: View {
    let descriptor: ModelDescriptor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ModelGlyph(descriptor: descriptor, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.name)
                        .font(Theme.Fonts.sans(15, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                    MonoText(subtitle, size: 11, color: selected ? Theme.Colors.accent : Theme.Colors.hint)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(selected ? Theme.Colors.accentBackground : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: selected ? 1.5 : 1))
            .opacity(descriptor.isAvailable ? 1 : 0.55)
        }
        .buttonStyle(PlainRowButtonStyle())
        .disabled(!descriptor.isAvailable)
        .accessibilityIdentifier("model.choice")
    }

    private var subtitle: String {
        if let reason = descriptor.unavailableReason { return reason }
        var parts = [descriptor.detail]
        if descriptor.kind == .gguf, let size = descriptor.sizeBytes { parts = [descriptor.detail.components(separatedBy: " · ").first ?? descriptor.detail, Format.bytes(size)] }
        if let tps = descriptor.measuredTokensPerSecond { parts.append(Format.tokensPerSecond(tps, fractionDigits: 0)) }
        return parts.joined(separator: " · ")
    }
}

struct ModelGlyph: View {
    let descriptor: ModelDescriptor
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(descriptor.kind == .apple ? Theme.Colors.accent : Theme.Colors.surfaceMuted)
            .frame(width: size, height: size)
            .overlay {
                if descriptor.kind == .apple {
                    Image(systemName: "apple.logo")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white)
                } else {
                    Text(descriptor.glyph)
                        .font(Theme.Fonts.mono(size * 0.32))
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
    }
}

/// iOS sheet for choosing the persona of the current chat.
struct PersonaPickerSheet: View {
    @Bindable var session: ChatSession
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Persona.sortOrder) private var personas: [Persona]

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Theme.Colors.borderStrong).frame(width: 38, height: 4).padding(.top, 12)
            HStack(alignment: .firstTextBaseline) {
                Text("Persona")
                    .font(Theme.Fonts.sans(21, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
            }
            .padding(.horizontal, 22)
            ScrollView {
                VStack(spacing: 8) {
                    personaRow(nil)
                    ForEach(personas) { persona in
                        personaRow(persona)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 34)
            }
        }
        .background(Theme.Colors.surface)
    }

    private func personaRow(_ persona: Persona?) -> some View {
        let selected = session.conversation.personaID == persona?.id
        return Button {
            session.setPersona(persona)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(persona?.name ?? "No persona")
                        .font(Theme.Fonts.sans(15, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                    Text(persona?.summary ?? "Plain assistant, no system prompt.")
                        .font(Theme.Fonts.sans(12))
                        .foregroundStyle(Theme.Colors.hint)
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(16)
            .background(selected ? Theme.Colors.accentBackground : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(PlainRowButtonStyle())
    }
}
