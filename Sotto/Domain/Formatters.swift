import Foundation

enum Format {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func integer(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "4.7 GB", "911 MB", "0 B". Uses decimal units to match vendor-quoted file sizes.
    static func bytes(_ value: Int64) -> String {
        bytes(UInt64(max(value, 0)))
    }

    static func bytes(_ value: UInt64) -> String {
        let gb = 1_000_000_000.0
        let mb = 1_000_000.0
        let kb = 1_000.0
        let double = Double(value)
        if double >= gb {
            return trimmed(double / gb, digits: 1) + " GB"
        }
        if double >= mb {
            return trimmed(double / mb, digits: 0) + " MB"
        }
        if double >= kb {
            return trimmed(double / kb, digits: 0) + " KB"
        }
        return "\(value) B"
    }

    /// "11.4 MB/s"
    static func bytesPerSecond(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        return bytes(UInt64(value)) + "/s"
    }

    /// "41.2 tok/s" or "~58 tok/s" when approximate.
    static func tokensPerSecond(_ value: Double, approximate: Bool = false, fractionDigits: Int = 1) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        let prefix = approximate ? "~" : ""
        return prefix + trimmed(value, digits: fractionDigits) + " tok/s"
    }

    /// "1.9s", "0.7s", "12s"
    static func seconds(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        if value >= 10 { return "\(Int(value.rounded()))s" }
        return trimmed(value, digits: 1) + "s"
    }

    /// "2 min left", "45 s left", "under a minute"
    static func remaining(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds < 60 { return "\(Int(seconds.rounded())) s left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min left" }
        let hours = minutes / 60
        return "\(hours) h \(minutes % 60) min left"
    }

    /// "8K", "32K", "128K", "4096"
    static func contextLength(_ tokens: Int) -> String {
        guard tokens > 0 else { return "—" }
        if tokens % 1024 == 0 { return "\(tokens / 1024)K" }
        if tokens >= 1000 { return trimmed(Double(tokens) / 1000, digits: 1) + "K" }
        return String(tokens)
    }

    /// "Aug 24"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static func trimmed(_ value: Double, digits: Int) -> String {
        let formatted = String(format: "%.\(digits)f", value)
        if digits == 0 { return formatted }
        var text = formatted
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Buckets used by the sidebar to group conversations.
enum ConversationGroup: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case previousWeek = "Previous 7 days"
    case earlier = "Earlier"

    var id: String { rawValue }

    static func group(for date: Date, relativeTo now: Date = .now, calendar: Calendar = .current) -> ConversationGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return .previousWeek
        }
        return .earlier
    }
}
