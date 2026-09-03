import Foundation
import os
import SwiftData

enum ToolExecutionError: LocalizedError, Equatable {
    case unknownTool(String)
    case invalidArguments(String)
    case unsupportedOnThisPlatform
    case invalidURL(String)
    case insecureURL
    case httpStatus(Int)
    case timeout
    case commandFailed(Int32, String)
    case emptyCommand
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "No enabled tool is called “\(name)”."
        case .invalidArguments(let detail): return "Invalid arguments: \(detail)."
        case .unsupportedOnThisPlatform: return "This build of Sotto cannot run shell tools."
        case .invalidURL(let url): return "The tool's address is not a valid URL: \(url)"
        case .insecureURL: return "Tools may only call https:// addresses."
        case .httpStatus(let code): return "The server answered with HTTP \(code)."
        case .timeout: return "The tool took longer than \(Int(ToolExecutor.timeout)) seconds."
        case .commandFailed(let code, let output): return "The command exited with status \(code).\(output.isEmpty ? "" : " \(output)")"
        case .emptyCommand: return "The tool has no command to run."
        case .notConfigured(let missing): return "This tool still needs \(missing). Open Tools to add it."
        }
    }
}

/// Runs one tool with the arguments the model chose. Approval and bookkeeping happen in the caller.
struct ToolExecutor {
    let settings: SettingsStore
    let context: ModelContext

    static let timeout: TimeInterval = 20

    func execute(_ definition: ToolDefinition, arguments: [String: Any]) async -> ToolRunResult {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (text, bytes) = try await run(definition, arguments: arguments)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.isEmpty ? "(the tool returned nothing)" : trimmed
            let capped = body.count > ToolDefinition.maximumResultCharacters
                ? String(body.prefix(ToolDefinition.maximumResultCharacters)) + "\n[truncated]"
                : body
            Log.engine.info("Tool \(definition.name, privacy: .public) succeeded in \(String(format: "%.2f", Self.seconds(start.duration(to: clock.now))), privacy: .public)s")
            return ToolRunResult(text: capped, success: true, denied: false, bytesSent: bytes, durationSeconds: Self.seconds(start.duration(to: clock.now)))
        } catch {
            Log.engine.error("Tool \(definition.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return ToolRunResult(text: "Error: \(error.localizedDescription)", success: false, denied: false, bytesSent: 0, durationSeconds: Self.seconds(start.duration(to: clock.now)))
        }
    }

    static func decodeArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func run(_ definition: ToolDefinition, arguments: [String: Any]) async throws -> (String, Int64) {
        try Self.validate(arguments, against: definition.parameters)
        switch definition.kind {
        case .builtIn:
            guard let builtIn = definition.builtIn else { throw ToolExecutionError.unknownTool(definition.name) }
            return (try BuiltInTools.run(builtIn, arguments: arguments, context: context), 0)
        case .httpRequest:
            guard let config = definition.httpConfig else { throw ToolExecutionError.invalidURL("") }
            return try await HTTPTool.run(config, arguments: arguments, settings: settings)
        case .webSearch:
            guard let config = definition.webSearchConfig, !config.searchEngineID.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ToolExecutionError.notConfigured("a Programmable Search Engine id")
            }
            guard let key = definition.apiKey, !key.isEmpty else {
                throw ToolExecutionError.notConfigured("a Google API key")
            }
            return try await WebSearchTool.run(config, apiKey: key, arguments: arguments, settings: settings)
        case .shellCommand:
            guard ToolKind.shellCommand.isAvailableOnThisPlatform else {
                throw ToolExecutionError.unsupportedOnThisPlatform
            }
            guard let config = definition.shellConfig else { throw ToolExecutionError.emptyCommand }
            return (try await ShellTool.run(config, arguments: arguments), 0)
        }
    }

    static func validate(_ arguments: [String: Any], against parameters: [ToolParameter]) throws {
        for parameter in parameters where parameter.isRequired {
            guard let value = arguments[parameter.name], !(value is NSNull) else {
                throw ToolExecutionError.invalidArguments("missing “\(parameter.name)”")
            }
            if parameter.type == .number, ToolTemplate.doubleValue(value) == nil {
                throw ToolExecutionError.invalidArguments("“\(parameter.name)” must be a number")
            }
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// MARK: - Template substitution

enum ToolTemplate {
    /// Replaces `{name}` placeholders with argument values. `encode` escapes each value for its context.
    static func substitute(_ template: String, arguments: [String: Any], encode: (String) -> String) -> String {
        var output = template
        for (key, value) in arguments {
            output = output.replacingOccurrences(of: "{\(key)}", with: encode(displayString(value)))
        }
        return output
    }

    static func displayString(_ value: Any) -> String {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let double = number.doubleValue
            if double == double.rounded(), abs(double) < 1e15 { return String(Int64(double)) }
            return "\(double)"
        case let text as String:
            return text
        default:
            return "\(value)"
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return displayString(number) }
        return nil
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): return number.doubleValue
        case let text as String: return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

// MARK: - HTTPS tool

enum HTTPTool {
    static func run(_ config: HTTPToolConfig, arguments: [String: Any], settings: SettingsStore) async throws -> (String, Int64) {
        let urlString = ToolTemplate.substitute(config.urlTemplate, arguments: arguments) { value in
            value.addingPercentEncoding(withAllowedCharacters: .sottoURLValueAllowed) ?? value
        }
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            throw ToolExecutionError.invalidURL(urlString)
        }
        guard url.scheme?.lowercased() == "https" else { throw ToolExecutionError.insecureURL }

        var request = URLRequest(url: url)
        request.httpMethod = config.method.uppercased() == "POST" ? "POST" : "GET"
        request.timeoutInterval = ToolExecutor.timeout
        request.setValue("Sotto/1.0 (local-first chat client)", forHTTPHeaderField: "User-Agent")
        for (name, value) in config.headers {
            request.setValue(ToolTemplate.substitute(value, arguments: arguments) { $0 }, forHTTPHeaderField: name)
        }
        if request.httpMethod == "POST", !config.bodyTemplate.isEmpty {
            let body = ToolTemplate.substitute(config.bodyTemplate, arguments: arguments) { value in
                value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
            }
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response, sent) = try await AccountedURLSession.perform(request)
        settings.recordBytesSent(sent)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ToolExecutionError.httpStatus(http.statusCode) }
        let body = String(decoding: data.prefix(200_000), as: UTF8.self)
        return (extract(path: config.responsePath, from: body), sent)
    }

    /// Follows a dot path (`a.b.0.c`) into a JSON body. Returns the whole body when the path is
    /// empty or does not resolve.
    static func extract(path: String, from body: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = body.data(using: .utf8),
              var node = try? JSONSerialization.jsonObject(with: data) else { return body }
        for component in trimmed.split(separator: ".") {
            if let dictionary = node as? [String: Any], let next = dictionary[String(component)] {
                node = next
            } else if let array = node as? [Any], let index = Int(component), array.indices.contains(index) {
                node = array[index]
            } else {
                return body
            }
        }
        if let text = node as? String { return text }
        if let number = node as? NSNumber { return ToolTemplate.displayString(number) }
        if JSONSerialization.isValidJSONObject(node),
           let encoded = try? JSONSerialization.data(withJSONObject: node, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: encoded, as: UTF8.self)
        }
        return "\(node)"
    }
}

extension CharacterSet {
    /// Percent-encoding set for a value dropped into a URL, so an argument cannot add parameters.
    static let sottoURLValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#/")
        return set
    }()
}

// MARK: - Shell tool (macOS only)

enum ShellTool {
    static func run(_ config: ShellToolConfig, arguments: [String: Any]) async throws -> String {
        #if os(macOS) && SOTTO_SHELL_TOOL
        let template = config.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { throw ToolExecutionError.emptyCommand }
        // Every substituted value is single-quoted, so an argument is data, never syntax.
        let command = ToolTemplate.substitute(template, arguments: arguments) { value in
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return try await withCheckedThrowingContinuation { continuation in
            let box = SingleResume(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            let deadline = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    box.resume(.failure(ToolExecutionError.timeout))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + ToolExecutor.timeout, execute: deadline)
            process.terminationHandler = { finished in
                deadline.cancel()
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 {
                    box.resume(.success(out.isEmpty ? err : out))
                } else {
                    box.resume(.failure(ToolExecutionError.commandFailed(finished.terminationStatus, err.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
            }
            do {
                try process.run()
            } catch {
                deadline.cancel()
                box.resume(.failure(error))
            }
        }
        #else
        throw ToolExecutionError.unsupportedOnThisPlatform
        #endif
    }

    /// The timeout handler and the termination handler race; only the first one may resume.
    private final class SingleResume: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Error>?

        init(_ continuation: CheckedContinuation<String, Error>) {
            self.continuation = continuation
        }

        func resume(_ result: Result<String, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }
}

// MARK: - Built-in tools

enum BuiltInTools {
    /// Dispatch only: every case is one line so this stays readable as tools are added, and the
    /// switch stays exhaustive so a new `BuiltInToolID` cannot ship without an implementation.
    static func run(_ tool: BuiltInToolID, arguments: [String: Any], context: ModelContext) throws -> String {
        switch tool {
        case .currentDateTime: return currentDateTime()
        case .calculator: return try calculate(ToolArguments.text(arguments, "expression"))
        case .unitConverter: return try convertUnits(arguments)
        case .textStatistics: return textStatistics(try ToolArguments.text(arguments, "text"))
        case .searchConversations: return searchConversations(try ToolArguments.text(arguments, "query"), context: context)

        case .dateDifference: return try DateTools.difference(arguments)
        case .dateShift: return try DateTools.shift(arguments)
        case .timeInZone: return try DateTools.timeInZone(arguments)
        case .calendarFacts: return try DateTools.facts(arguments)

        case .transformText: return try TextTools.transform(arguments)
        case .replaceText: return try TextTools.replace(arguments)
        case .extractMatches: return try TextTools.extract(arguments)
        case .sortLines: return try TextTools.sortLines(arguments)
        case .wordFrequency: return try TextTools.wordFrequency(arguments)
        case .compareTexts: return try TextTools.compare(arguments)

        case .formatJSON: return try DataTools.formatJSON(arguments)
        case .queryJSON: return try DataTools.queryJSON(arguments)
        case .summarizeCSV: return try DataTools.summariseCSV(arguments)
        case .describeNumbers: return try DataTools.describeNumbers(arguments)
        case .percentage: return try DataTools.percentage(arguments)
        case .convertBase: return try DataTools.convertBase(arguments)

        case .encodeText: return try EncodingTools.encode(arguments)
        case .hashText: return try EncodingTools.hash(arguments)
        case .randomNumber: return try EncodingTools.random(arguments)
        case .estimateTokens: return try EncodingTools.estimateTokens(arguments)
        }
    }

    private static func convertUnits(_ arguments: [String: Any]) throws -> String {
        try convert(
            value: ToolArguments.number(arguments, "value"),
            from: ToolArguments.text(arguments, "from"),
            to: ToolArguments.text(arguments, "to")
        )
    }

    static func currentDateTime(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        let iso = ISO8601DateFormatter()
        return "\(formatter.string(from: now)) — ISO 8601 \(iso.string(from: now)), time zone \(TimeZone.current.identifier)"
    }

    static func calculate(_ expression: String) throws -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolExecutionError.invalidArguments("the expression is empty") }
        do {
            let value = try Arithmetic.evaluate(trimmed)
            return "\(trimmed) = \(formatNumber(value))"
        } catch let error as Arithmetic.EvaluationError {
            throw ToolExecutionError.invalidArguments(error.localizedDescription)
        }
    }

    static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static let units: [String: Dimension] = [
        "m": UnitLength.meters, "meter": UnitLength.meters, "meters": UnitLength.meters, "metre": UnitLength.meters, "metres": UnitLength.meters,
        "km": UnitLength.kilometers, "kilometer": UnitLength.kilometers, "kilometers": UnitLength.kilometers, "kilometre": UnitLength.kilometers, "kilometres": UnitLength.kilometers,
        "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "ft": UnitLength.feet, "foot": UnitLength.feet, "feet": UnitLength.feet,
        "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
        "yd": UnitLength.yards, "yard": UnitLength.yards, "yards": UnitLength.yards,
        "kg": UnitMass.kilograms, "kilogram": UnitMass.kilograms, "kilograms": UnitMass.kilograms,
        "g": UnitMass.grams, "gram": UnitMass.grams, "grams": UnitMass.grams,
        "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pound": UnitMass.pounds, "pounds": UnitMass.pounds,
        "oz": UnitMass.ounces, "ounce": UnitMass.ounces, "ounces": UnitMass.ounces,
        "c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "l": UnitVolume.liters, "liter": UnitVolume.liters, "liters": UnitVolume.liters, "litre": UnitVolume.liters, "litres": UnitVolume.liters,
        "ml": UnitVolume.milliliters, "gal": UnitVolume.gallons, "gallon": UnitVolume.gallons, "gallons": UnitVolume.gallons,
        "cup": UnitVolume.cups, "cups": UnitVolume.cups, "floz": UnitVolume.fluidOunces,
        "mph": UnitSpeed.milesPerHour, "kph": UnitSpeed.kilometersPerHour, "kmh": UnitSpeed.kilometersPerHour,
        "m/s": UnitSpeed.metersPerSecond, "kn": UnitSpeed.knots, "knots": UnitSpeed.knots,
        "s": UnitDuration.seconds, "sec": UnitDuration.seconds, "second": UnitDuration.seconds, "seconds": UnitDuration.seconds,
        "min": UnitDuration.minutes, "minute": UnitDuration.minutes, "minutes": UnitDuration.minutes,
        "h": UnitDuration.hours, "hr": UnitDuration.hours, "hour": UnitDuration.hours, "hours": UnitDuration.hours,
        "b": UnitInformationStorage.bytes, "byte": UnitInformationStorage.bytes, "bytes": UnitInformationStorage.bytes,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
    ]

    static func convert(value: Double, from: String, to: String) throws -> String {
        let sourceKey = from.lowercased().trimmingCharacters(in: .whitespaces)
        let targetKey = to.lowercased().trimmingCharacters(in: .whitespaces)
        guard let source = units[sourceKey] else { throw ToolExecutionError.invalidArguments("unknown unit “\(from)”") }
        guard let target = units[targetKey] else { throw ToolExecutionError.invalidArguments("unknown unit “\(to)”") }
        guard type(of: source) == type(of: target) else {
            throw ToolExecutionError.invalidArguments("\(from) and \(to) measure different things")
        }
        let converted = Measurement(value: value, unit: source).converted(to: target)
        let rounded = (converted.value * 10_000).rounded() / 10_000
        return "\(formatNumber(value)) \(source.symbol) = \(formatNumber(rounded)) \(target.symbol)"
    }

    static func textStatistics(_ text: String) -> String {
        let characters = text.count
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let sentences = text.split(whereSeparator: { ".!?".contains($0) })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let minutes = words == 0 ? 0 : max(1, Int((Double(words) / 220).rounded(.up)))
        return "\(characters) characters, \(words) words, \(sentences) sentences, about \(minutes) min to read"
    }

    static func searchConversations(_ query: String, context: ModelContext) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "No search words were given." }
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.text.localizedStandardContains(needle) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let matches = (try? context.fetch(descriptor)) ?? []
        guard !matches.isEmpty else { return "No earlier message mentions “\(needle)”." }
        let lines = matches.prefix(5).map { message -> String in
            let title = message.conversation?.title ?? "Untitled chat"
            let flattened = message.text.replacingOccurrences(of: "\n", with: " ")
            let excerpt = flattened.count > 160 ? String(flattened.prefix(160)) + "…" : flattened
            return "- [\(title) · \(message.role.rawValue) · \(Format.shortDate(message.createdAt))] \(excerpt)"
        }
        return "\(matches.count) matching message\(matches.count == 1 ? "" : "s"):\n" + lines.joined(separator: "\n")
    }
}
