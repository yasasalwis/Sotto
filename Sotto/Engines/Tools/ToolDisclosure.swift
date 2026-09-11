import Foundation

/// What a person is told before a tool runs: what the call does, whether anything leaves the
/// device, and where it goes. Built once per approval and shown on the card above the composer,
/// so the wording lives in one place and can be tested without a conversation behind it.
///
/// App Review guidelines 5.1.1(i) and 5.1.2(i) ask that an app say what data is sent and to whom,
/// and ask permission, before anything personal leaves the device. For Sotto the only tools that
/// send anything are the Google search tool and HTTPS tools the person wrote themselves, and in
/// both cases what leaves is the argument values the model chose — never the conversation.
struct ToolDisclosure: Equatable, Sendable {
    /// One line describing the call: the search words, the request, or the command.
    let effect: String
    /// True when the argument values the model chose are sent off the device.
    let leavesDevice: Bool
    /// The host that receives them, when it can be read from the tool's configuration.
    let destinationHost: String?
    /// One or two plain sentences: what is sent and to whom, or that nothing leaves the device.
    let dataSentSummary: String

    static let googleSearchHost = "www.googleapis.com"

    static func make(for definition: ToolDefinition, arguments: [String: Any]) -> ToolDisclosure {
        switch definition.kind {
        case .builtIn:
            return builtIn(definition)
        case .webSearch:
            return webSearch(definition, arguments: arguments)
        case .httpRequest:
            return httpRequest(definition, arguments: arguments)
        case .shellCommand:
            let command = ToolTemplate.substitute(definition.shellConfig?.command ?? "", arguments: arguments) { $0 }
            return ToolDisclosure(
                effect: command,
                leavesDevice: false,
                destinationHost: nil,
                dataSentSummary: "Runs on this Mac as you. Sotto sends nothing anywhere."
            )
        }
    }

    private static func builtIn(_ definition: ToolDefinition) -> ToolDisclosure {
        let effect = definition.builtIn == .delegate
            ? "Runs a second model session on this device."
            : "Runs on this device."
        return ToolDisclosure(
            effect: effect,
            leavesDevice: false,
            destinationHost: nil,
            dataSentSummary: "Nothing leaves this device."
        )
    }

    private static func webSearch(_ definition: ToolDefinition, arguments: [String: Any]) -> ToolDisclosure {
        let query = ToolTemplate.stringValue(arguments["query"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let site = definition.webSearchConfig?.site.trimmingCharacters(in: .whitespaces) ?? ""
        return ToolDisclosure(
            effect: "Search Google for “\(query)”" + (site.isEmpty ? "" : " on \(site)"),
            leavesDevice: true,
            destinationHost: googleSearchHost,
            dataSentSummary: "Sends only these search words to Google (\(googleSearchHost)), under your own API key. Nothing else from this chat is sent."
        )
    }

    private static func httpRequest(_ definition: ToolDefinition, arguments: [String: Any]) -> ToolDisclosure {
        let method = definition.httpConfig?.method.uppercased() ?? "GET"
        let url = ToolTemplate.substitute(definition.httpConfig?.urlTemplate ?? "", arguments: arguments) { $0 }
        let host = URL(string: url)?.host?.lowercased()
        let destination = host.map { "\($0), the address this tool was set up with" } ?? "the address this tool was set up with"
        return ToolDisclosure(
            effect: "\(method) \(url)",
            leavesDevice: true,
            destinationHost: host,
            dataSentSummary: "Sends only the argument values above to \(destination). Nothing else from this chat is sent."
        )
    }
}
