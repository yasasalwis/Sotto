import SwiftUI

struct InspectorView: View {
    let session: ChatSession?
    @Environment(AppServices.self) private var services
    @State private var footprint: UInt64 = DeviceCapabilities.processFootprintBytes()
    @State private var thermal = DeviceCapabilities.thermalStateLabel

    private var throughput: Double? {
        if let session, session.conversation.modelRef.isApple {
            return session.conversation.orderedMessages.last(where: { $0.tokensPerSecond != nil })?.tokensPerSecond ?? AppleThroughput.lastMeasured
        }
        return services.runtime.lastTokensPerSecond ?? session?.conversation.orderedMessages.last(where: { $0.tokensPerSecond != nil })?.tokensPerSecond
    }

    private var samples: [Double] {
        if let session, session.conversation.modelRef.isApple {
            let values = session.conversation.orderedMessages.compactMap(\.tokensPerSecond).suffix(ModelRuntime.throughputSampleCount)
            return Array(values)
        }
        return services.runtime.throughputHistory
    }

    private var contextFraction: Double {
        guard let session, session.contextLength > 0 else { return 0 }
        return min(Double(session.contextTokensUsed) / Double(session.contextLength), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel("Inspector", color: Theme.Colors.mutedLight)
                .frame(height: 42)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .hairlineDivider(Theme.Colors.hairlinePanel)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    throughputSection
                    HairlineRule()
                    VStack(alignment: .leading, spacing: 12) {
                        StatRow(label: "Memory", value: Format.bytes(footprint))
                        StatRow(label: "Context", value: Format.percent(contextFraction))
                        ThinProgressBar(value: contextFraction)
                        StatRow(label: "Thermal", value: thermal, valueColor: thermal == "nominal" ? Theme.Colors.accent : Theme.Colors.danger)
                        StatRow(label: "Network", value: "\(Format.bytes(services.settings.bytesSentThisMonth)) sent")
                        StatRow(label: "Model", value: services.runtime.state.label, valueColor: Theme.Colors.hint)
                    }
                    HairlineRule()
                    samplingSection
                    HairlineRule()
                    if let session {
                        PrivateCloudComputeRow(compact: true, allowsOverride: session.conversation.allowsPrivateCloudCompute) { session.conversation.allowsPrivateCloudCompute = $0 }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .background(Theme.Colors.panel)
        .task {
            while !Task.isCancelled {
                footprint = DeviceCapabilities.processFootprintBytes()
                thermal = DeviceCapabilities.thermalStateLabel
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Throughput")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(throughput.map { String(format: "%.1f", $0) } ?? "—")
                    .font(Theme.Fonts.mono(28))
                    .foregroundStyle(Theme.Colors.ink)
                MonoText("tok/s", size: 12)
            }
            if samples.isEmpty {
                MonoText("no samples yet", size: 10, color: Theme.Colors.faint)
                    .frame(height: 34, alignment: .bottom)
            } else {
                BarSparkline(samples: samples)
            }
        }
    }

    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Sampling")
            if let session {
                let resolved = SamplingSettings.resolve(persona: session.persona, conversation: session.conversation)
                SamplingSlider(label: "Temperature", value: String(format: "%.1f", resolved.temperature), fraction: resolved.temperature / Persona.temperatureRange.upperBound) { fraction in
                    session.conversation.temperatureOverride = (fraction * Persona.temperatureRange.upperBound * 10).rounded() / 10
                }
                SamplingSlider(label: "Top-p", value: String(format: "%.2f", resolved.topP), fraction: resolved.topP) { fraction in
                    session.conversation.topPOverride = max(Persona.topPRange.lowerBound, (fraction * 100).rounded() / 100)
                }
                SamplingSlider(label: "Max tokens", value: Format.integer(resolved.maxTokens), fraction: Double(resolved.maxTokens) / Double(Persona.maxTokensRange.upperBound)) { fraction in
                    let raw = Int(fraction * Double(Persona.maxTokensRange.upperBound))
                    session.conversation.maxTokensOverride = max(Persona.maxTokensRange.lowerBound, (raw / 64) * 64)
                }
                if session.conversation.temperatureOverride != nil || session.conversation.topPOverride != nil || session.conversation.maxTokensOverride != nil {
                    Button("Reset to persona defaults") {
                        session.conversation.temperatureOverride = nil
                        session.conversation.topPOverride = nil
                        session.conversation.maxTokensOverride = nil
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            } else {
                MonoText("open a chat to tune sampling", size: 10, color: Theme.Colors.faint)
            }
        }
    }
}

/// A 3pt slider matching the inspector's design; drag anywhere on the track.
struct SamplingSlider: View {
    let label: String
    let value: String
    let fraction: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 7) {
            StatRow(label: label, value: value)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.border)
                    Capsule().fill(Theme.Colors.textSecondary).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
                .frame(height: 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            onChange(min(max(drag.location.x / proxy.size.width, 0), 1))
                        }
                )
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(fraction + 0.05, 1))
            case .decrement: onChange(max(fraction - 0.05, 0))
            @unknown default: break
            }
        }
    }
}
