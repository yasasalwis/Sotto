import SwiftUI

/// One tool call shown under the assistant's reply. Tapping it reveals what came back.
struct ToolCallRow: View {
    let record: ToolCallRecord
    @State private var isExpanded = false

    private var statusColor: Color {
        switch record.status {
        case .succeeded: return Theme.Colors.accent
        case .failed: return Theme.Colors.danger
        case .denied: return Theme.Colors.hint
        case .running, .awaitingApproval: return Theme.Colors.accent
        }
    }

    private var trailingText: String {
        switch record.status {
        case .succeeded:
            var parts = [Format.seconds(record.durationSeconds)]
            if record.bytesSent > 0 { parts.append("\(Format.bytes(record.bytesSent)) sent") }
            return parts.joined(separator: " · ")
        default:
            return record.status.label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard !record.resultText.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    if record.status == .running || record.status == .awaitingApproval {
                        TypingDots()
                            .frame(width: 23)
                    } else {
                        Image(systemName: record.status == .succeeded ? "checkmark" : (record.status == .failed ? "exclamationmark.triangle" : "minus"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .frame(width: 23)
                    }
                    Text(record.displayName)
                        .font(Theme.Fonts.sans(13, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                    if !record.argumentsSummary.isEmpty {
                        MonoText(record.argumentsSummary, size: 11, color: Theme.Colors.hint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    MonoText(trailingText, size: 10, color: statusColor)
                    if !record.resultText.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.placeholder)
                    }
                }
            }
            .buttonStyle(PlainRowButtonStyle())
            if isExpanded, !record.resultText.isEmpty {
                ScrollView {
                    Text(record.resultText)
                        .font(Theme.Fonts.mono(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card(radius: 10, background: Theme.Colors.panel, border: Theme.Colors.border)
        .accessibilityIdentifier("message.toolCall")
        .accessibilityLabel("\(record.displayName), \(record.status.label)")
    }
}

/// Asks before a tool runs. Shown above the composer while a call is waiting.
struct ToolApprovalCard: View {
    let approval: PendingToolApproval
    let onDecision: (ToolApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ToolGlyph(kind: approval.kind, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run \(approval.displayName)?")
                        .font(Theme.Fonts.sans(14, weight: .medium))
                        .foregroundStyle(Theme.Colors.ink)
                    MonoText(approval.toolName, size: 10, color: Theme.Colors.hint)
                }
                Spacer()
                if approval.kind == .httpRequest {
                    labelBadge("leaves this device", accent: false)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !approval.argumentsSummary.isEmpty {
                    MonoText(approval.argumentsSummary, size: 11, color: Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(approval.effect)
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 8) {
                Button("Allow once") { onDecision(.allowOnce) }
                    .buttonStyle(PrimaryButtonStyle(size: 13, horizontalPadding: 14, verticalPadding: 7))
                    .accessibilityIdentifier("tool.allowOnce")
                Button("Always allow") { onDecision(.allowAlways) }
                    .buttonStyle(SecondaryButtonStyle(size: 13, horizontalPadding: 14, verticalPadding: 7))
                Spacer()
                Button("Don't run") { onDecision(.deny) }
                    .buttonStyle(SecondaryButtonStyle(size: 13, horizontalPadding: 14, verticalPadding: 7, foreground: Theme.Colors.danger, border: Theme.Colors.dangerBorder))
                    .accessibilityIdentifier("tool.deny")
            }
        }
        .padding(14)
        .card(radius: Theme.Radius.card, background: Theme.Colors.accentBackground, border: Theme.Colors.accentSoft)
        .accessibilityIdentifier("tool.approval")
    }
}
