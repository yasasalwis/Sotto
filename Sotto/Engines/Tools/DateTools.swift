import Foundation

/// The four calendar built-ins. Everything runs against the device's own calendar and time zone;
/// nothing here reaches the network.
enum DateTools {
    // MARK: - Parsing

    /// Formats accepted for a date argument, in the order they are tried. `en_US_POSIX` is used so
    /// the model may write "3 September 2026" whatever the device's language is.
    private static let patterns = [
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd", "dd/MM/yyyy", "MM/dd/yyyy",
        "d MMMM yyyy", "MMMM d, yyyy", "MMMM d yyyy", "d MMM yyyy", "MMM d, yyyy", "MMM d yyyy",
    ]

    /// True when the text carried no clock time, so the value means a whole day.
    struct ParsedDate {
        var date: Date
        var isDateOnly: Bool
    }

    /// Reads a date argument. Accepts ISO 8601, the common written forms, and the words a model
    /// reaches for when the user said "today". Returns nil when nothing matches, so the caller can
    /// name the offending argument in the error.
    static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> ParsedDate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "now": return ParsedDate(date: now, isDateOnly: false)
        case "today": return ParsedDate(date: calendar.startOfDay(for: now), isDateOnly: true)
        case "tomorrow", "yesterday":
            let step = trimmed.lowercased() == "tomorrow" ? 1 : -1
            guard let shifted = calendar.date(byAdding: .day, value: step, to: now) else { return nil }
            return ParsedDate(date: calendar.startOfDay(for: shifted), isDateOnly: true)
        default: break
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for pattern in patterns {
            formatter.dateFormat = pattern
            guard let date = formatter.date(from: trimmed) else { continue }
            let dateOnly = !pattern.contains("H")
            return ParsedDate(date: dateOnly ? calendar.startOfDay(for: date) : date, isDateOnly: dateOnly)
        }
        return nil
    }

    static func requireDate(_ arguments: [String: Any], _ key: String, fallback: Date? = nil, now: Date = .now, calendar: Calendar = .current) throws -> ParsedDate {
        guard let raw = ToolTemplate.stringValue(arguments[key])?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            guard let fallback else {
                throw ToolExecutionError.invalidArguments("“\(key)” is required, for example 2026-09-03")
            }
            return ParsedDate(date: fallback, isDateOnly: false)
        }
        guard let parsed = parse(raw, now: now, calendar: calendar) else {
            throw ToolExecutionError.invalidArguments("“\(raw)” is not a date I can read; use YYYY-MM-DD")
        }
        return parsed
    }

    /// "Thursday 3 September 2026", or with the time when the value carries one.
    static func describe(_ parsed: ParsedDate, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = parsed.isDateOnly ? "EEEE d MMMM yyyy" : "EEEE d MMMM yyyy 'at' HH:mm"
        return formatter.string(from: parsed.date)
    }

    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - date_difference

    static func difference(_ arguments: [String: Any], now: Date = .now, calendar: Calendar = .current) throws -> String {
        let from = try requireDate(arguments, "from", now: now, calendar: calendar)
        let to = try requireDate(arguments, "to", fallback: now, now: now, calendar: calendar)
        let earlier = min(from.date, to.date)
        let later = max(from.date, to.date)
        let direction = to.date < from.date ? "earlier" : "later"

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier), to: calendar.startOfDay(for: later)).day ?? 0
        let breakdown = calendar.dateComponents([.year, .month, .day], from: earlier, to: later)
        var lines = [
            "\(describe(from, calendar: calendar)) → \(describe(to, calendar: calendar))",
            "\(Format.integer(days)) calendar day\(days == 1 ? "" : "s") \(direction)",
            "\(phrase(years: breakdown.year ?? 0, months: breakdown.month ?? 0, days: breakdown.day ?? 0))",
        ]
        if days != 0 {
            lines.append("\(Format.integer(days / 7)) week\(days / 7 == 1 ? "" : "s") and \(days % 7) day\(days % 7 == 1 ? "" : "s")")
        }
        if !from.isDateOnly || !to.isDateOnly {
            let seconds = Int(later.timeIntervalSince(earlier).rounded())
            lines.append("\(Format.integer(seconds / 3_600)) hours \(seconds % 3_600 / 60) minutes in total")
        }
        return lines.joined(separator: "\n")
    }

    private static func phrase(years: Int, months: Int, days: Int) -> String {
        var parts: [String] = []
        if years != 0 { parts.append("\(years) year\(abs(years) == 1 ? "" : "s")") }
        if months != 0 { parts.append("\(months) month\(abs(months) == 1 ? "" : "s")") }
        if days != 0 || parts.isEmpty { parts.append("\(days) day\(abs(days) == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    // MARK: - date_shift

    static let shiftUnits = ["days", "weeks", "months", "years", "hours", "minutes"]

    static func shift(_ arguments: [String: Any], now: Date = .now, calendar: Calendar = .current) throws -> String {
        let start = try requireDate(arguments, "date", fallback: calendar.startOfDay(for: now), now: now, calendar: calendar)
        let amount = Int(try ToolArguments.number(arguments, "amount").rounded())
        let unit = try ToolArguments.choice(arguments, "unit", from: shiftUnits)
        let component: Calendar.Component
        switch unit {
        case "weeks": component = .weekOfYear
        case "months": component = .month
        case "years": component = .year
        case "hours": component = .hour
        case "minutes": component = .minute
        default: component = .day
        }
        guard let result = calendar.date(byAdding: component, value: amount, to: start.date) else {
            throw ToolExecutionError.invalidArguments("\(amount) \(unit) from that date is outside the calendar")
        }
        let carriesTime = !start.isDateOnly || component == .hour || component == .minute
        let shifted = ParsedDate(date: result, isDateOnly: !carriesTime)
        let word = amount < 0 ? "before" : "after"
        return """
        \(abs(amount)) \(unit) \(word) \(describe(start, calendar: calendar))
        \(describe(shifted, calendar: calendar))
        ISO 8601: \(isoDay(result, calendar: calendar))
        """
    }

    // MARK: - time_in_zone

    static func timeInZone(_ arguments: [String: Any], now: Date = .now) throws -> String {
        let request = try ToolArguments.text(arguments, "zone").trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = zones(matching: request)
        guard let zone = matches.first else {
            throw ToolExecutionError.invalidArguments("“\(request)” is not a time zone I know; try a city such as Tokyo or an identifier such as Asia/Tokyo")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE d MMMM yyyy 'at' HH:mm"
        let offsetHours = Double(zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3_600
        var text = "\(zone.identifier): \(formatter.string(from: now)) (UTC\(gmtOffset(zone, at: now)))"
        if zone.identifier != TimeZone.current.identifier {
            text += "\n\(BuiltInTools.formatNumber(abs(offsetHours))) hour\(abs(offsetHours) == 1 ? "" : "s") "
            text += offsetHours == 0 ? "difference from" : (offsetHours > 0 ? "ahead of" : "behind")
            text += " this device (\(TimeZone.current.identifier))"
        }
        if matches.count > 1 {
            text += "\nOther zones matching “\(request)”: " + matches.dropFirst().prefix(4).map(\.identifier).joined(separator: ", ")
        }
        return text
    }

    /// Identifier, abbreviation, or the city portion of an identifier. Ordered so an exact
    /// identifier always wins over a city that merely contains the same letters.
    static func zones(matching request: String) -> [TimeZone] {
        let needle = request.lowercased().replacingOccurrences(of: " ", with: "_")
        if let exact = TimeZone(identifier: request) { return [exact] }
        if let abbreviated = TimeZone(abbreviation: request.uppercased()) { return [abbreviated] }
        let identifiers = TimeZone.knownTimeZoneIdentifiers
        let cityMatches = identifiers.filter { ($0.split(separator: "/").last?.lowercased() ?? "") == needle }
        let looseMatches = identifiers.filter { $0.lowercased().contains(needle) && !cityMatches.contains($0) }
        return (cityMatches + looseMatches).compactMap(TimeZone.init(identifier:))
    }

    private static func gmtOffset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        return String(format: "%@%02d:%02d", sign, abs(seconds) / 3_600, abs(seconds) % 3_600 / 60)
    }

    // MARK: - calendar_facts

    static func facts(_ arguments: [String: Any], now: Date = .now, calendar: Calendar = .current) throws -> String {
        let parsed = try requireDate(arguments, "date", fallback: calendar.startOfDay(for: now), now: now, calendar: calendar)
        let date = parsed.date
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .quarter], from: date)
        let year = parts.year ?? 0
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 0
        let isoParts = iso.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let names = DateFormatter()
        names.locale = Locale(identifier: "en_US_POSIX")
        names.calendar = calendar
        names.timeZone = calendar.timeZone
        names.dateFormat = "EEEE"
        let weekday = names.string(from: date)
        names.dateFormat = "MMMM"
        return """
        \(isoDay(date, calendar: calendar)) is a \(weekday)
        Month: \(names.string(from: date)) \(year), \(daysInMonth) days, quarter \(parts.quarter ?? 0)
        Day \(dayOfYear) of \(daysInYear); \(daysInYear - dayOfYear) day\(daysInYear - dayOfYear == 1 ? "" : "s") left in the year
        ISO week \(isoParts.weekOfYear ?? 0) of \(isoParts.yearForWeekOfYear ?? year)
        \(year) is \(leap ? "a leap year" : "not a leap year")
        """
    }
}
