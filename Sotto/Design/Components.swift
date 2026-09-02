import SwiftUI

// MARK: - Text primitives

struct MonoText: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = Theme.Colors.hint
    var weight: Font.Weight = .regular

    init(_ text: String, size: CGFloat = 11, color: Color = Theme.Colors.hint, weight: Font.Weight = .regular) {
        self.text = text
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .font(Theme.Fonts.mono(size, weight: weight))
            .foregroundStyle(color)
    }
}

/// Uppercased, letter-spaced mono label used for section headers.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.Colors.faint
    var size: CGFloat = 10

    init(_ text: String, color: Color = Theme.Colors.faint, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.mono(size))
            .tracking(size * 0.1)
            .foregroundStyle(color)
    }
}

// MARK: - Marks and indicators

struct LogoMark: View {
    var size: CGFloat = 20
    var radius: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? size * 0.29, style: .continuous)
            .fill(Theme.Colors.accent)
            .frame(width: size, height: size)
            .overlay {
                Text("s")
                    .font(Theme.Fonts.sans(size * 0.52, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.02)
            }
            .accessibilityHidden(true)
    }
}

/// Opens a public page in the browser. Used for the privacy, support and source links that
/// App Review and the App Store listing point at.
struct LinkRow: View {
    let title: String
    let url: URL

    init(_ title: String, url: URL) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                MonoText(title, size: 12, color: Theme.Colors.accent)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(url.host() ?? "link")")
    }
}

struct StatusDot: View {
    var color: Color = Theme.Colors.accent
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: 5, height: 5)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(360))
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
        .accessibilityLabel("Generating")
    }

    private func color(for index: Int) -> Color {
        let offset = (index - phase + 3) % 3
        switch offset {
        case 0: return Theme.Colors.accent
        case 1: return Theme.Colors.barMid
        default: return Theme.Colors.barLow
        }
    }
}

struct ThinProgressBar: View {
    var value: Double
    var height: CGFloat = 4
    var track: Color = Theme.Colors.border
    var fill: Color = Theme.Colors.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Chips and buttons

struct Chip: View {
    let text: String
    var active = false
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(Theme.Fonts.mono(size))
            .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.hint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Theme.Colors.accentPale : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(active ? Theme.Colors.accentSoft : Theme.Colors.border, lineWidth: 1)
            )
    }
}

struct ChipButtonStyle: ButtonStyle {
    var active = false
    var size: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.mono(size))
            .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.hint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                active ? Theme.Colors.accentTint : (configuration.isPressed ? Theme.Colors.surfaceMuted : Color.clear),
                in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(active ? Color.clear : Theme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var size: CGFloat = 13
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8
    var radius: CGFloat = Theme.Radius.control
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.sans(size, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                configuration.isPressed ? Theme.Colors.accentDark : Theme.Colors.accent,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var size: CGFloat = 13
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8
    var radius: CGFloat = Theme.Radius.control
    var fullWidth = false
    var foreground: Color = Theme.Colors.textSecondary
    var border: Color = Theme.Colors.borderStrong

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.sans(size, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                configuration.isPressed ? Theme.Colors.surfaceMuted : Color.clear,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

struct PlainRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Containers

struct CardModifier: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var background: Color = Theme.Colors.surface
    var border: Color = Theme.Colors.border
    var lineWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: lineWidth)
            )
    }
}

extension View {
    func card(radius: CGFloat = Theme.Radius.card, background: Color = Theme.Colors.surface, border: Color = Theme.Colors.border, lineWidth: CGFloat = 1) -> some View {
        modifier(CardModifier(radius: radius, background: background, border: border, lineWidth: lineWidth))
    }

    func hairlineDivider(_ color: Color = Theme.Colors.hairline) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(color).frame(height: 1)
        }
    }
}

struct HairlineRule: View {
    var color: Color = Theme.Colors.hairlinePanel

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// A labelled key/value line used across the inspector and settings.
struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.Colors.ink
    var labelSize: CGFloat = 13
    var valueSize: CGFloat = 12

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.sans(labelSize))
                .foregroundStyle(Theme.Colors.muted)
            Spacer()
            MonoText(value, size: valueSize, color: valueColor)
        }
    }
}

/// A large metric with a small mono caption beneath it ("41 tok/s" / "MEASURED").
struct MetricColumn: View {
    let value: String
    let caption: String
    var valueSize: CGFloat = 13
    var captionSize: CGFloat = 10
    var valueColor: Color = Theme.Colors.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MonoText(value, size: valueSize, color: valueColor)
            SectionLabel(caption, size: captionSize)
        }
    }
}

struct SottoToggleStyle: ToggleStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let width: CGFloat = compact ? 34 : 44
        let height: CGFloat = compact ? 20 : 26
        let knob = height - 4
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.Colors.accent : Theme.Colors.track)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(configuration.isOn ? 0 : 0.16), radius: 1, y: 1)
                        .frame(width: knob, height: knob)
                        .padding(2)
                }
                .frame(width: width, height: height)
                .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Sparkline for throughput

struct BarSparkline: View {
    let samples: [Double]
    var barWidth: CGFloat = 6
    var spacing: CGFloat = 3
    var height: CGFloat = 34

    var body: some View {
        let peak = max(samples.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: index, count: samples.count))
                    .frame(width: barWidth, height: max(height * sample / peak, 2))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityLabel("Throughput history")
    }

    private func color(for index: Int, count: Int) -> Color {
        let position = Double(index + 1) / Double(max(count, 1))
        if position > 0.62 { return Theme.Colors.accent }
        if position > 0.37 { return Theme.Colors.barMid }
        return Theme.Colors.barLow
    }
}
