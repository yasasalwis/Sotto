import Foundation
import os

/// Google Programmable Search, called with the user's own API key and search-engine id.
/// Results come back as a short numbered list rather than raw JSON so they cost little context.
enum WebSearchTool {
    static let endpoint = "https://www.googleapis.com/customsearch/v1"
    static let snippetLimit = 220
    static let setupURL = "https://programmablesearchengine.google.com/controlpanel/create"
    static let keyURL = "https://console.cloud.google.com/apis/credentials"

    struct Result: Hashable {
        var title: String
        var snippet: String
        var link: String
    }

    static func run(_ config: WebSearchConfig, apiKey: String, arguments: [String: Any], settings: SettingsStore) async throws -> (String, Int64) {
        guard let query = ToolTemplate.stringValue(arguments["query"])?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw ToolExecutionError.invalidArguments("query")
        }
        guard let url = makeURL(config, apiKey: apiKey, query: query) else {
            throw ToolExecutionError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = ToolExecutor.timeout
        request.setValue("Sotto/1.0 (local-first chat client)", forHTTPHeaderField: "User-Agent")
        let (data, response, sent) = try await AccountedURLSession.perform(request)
        settings.recordBytesSent(sent)

        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw ToolExecutionError.invalidArguments(failureMessage(status: http.statusCode, body: data))
        }
        let results = parse(data, limit: config.resultCount)
        guard !results.isEmpty else { return ("No results for “\(query)”.", sent) }
        return (format(results, query: query), sent)
    }

    static func makeURL(_ config: WebSearchConfig, apiKey: String, query: String) -> URL? {
        var terms = query
        let site = config.site.trimmingCharacters(in: .whitespaces)
        if !site.isEmpty {
            terms += " site:\(site)"
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: config.searchEngineID.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "q", value: terms),
            URLQueryItem(name: "num", value: String(min(max(config.resultCount, 1), 10))),
            URLQueryItem(name: "safe", value: config.safeSearch ? "active" : "off"),
        ]
        return components?.url
    }

    static func parse(_ data: Data, limit: Int) -> [Result] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return [] }
        return items.prefix(max(limit, 1)).map { item in
            let snippet = (item["snippet"] as? String ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(
                title: (item["title"] as? String ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines),
                snippet: snippet.count > snippetLimit ? String(snippet.prefix(snippetLimit)) + "…" : snippet,
                link: item["link"] as? String ?? ""
            )
        }
    }

    static func format(_ results: [Result], query: String) -> String {
        var text = "Google results for “\(query)”:\n"
        for (index, result) in results.enumerated() {
            text += "\n\(index + 1). \(result.title)\n"
            if !result.snippet.isEmpty { text += "   \(result.snippet)\n" }
            if !result.link.isEmpty { text += "   \(result.link)\n" }
        }
        text += "\nThese are search results, not verified facts. Say where an answer came from."
        return text
    }

    /// Google explains most failures in the body; surface that rather than a bare status code.
    static func failureMessage(status: Int, body: Data) -> String {
        var detail = ""
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            detail = " " + message
        }
        switch status {
        case 400:
            return "Google rejected the request. Check the search engine id (cx) in the tool's settings.\(detail)"
        case 403:
            return "Google refused the key. Check that the Custom Search API is enabled for it and the daily quota is not spent.\(detail)"
        case 429:
            return "Google's daily quota for this key is used up. The free tier allows 100 searches a day.\(detail)"
        default:
            return "Google answered with HTTP \(status).\(detail)"
        }
    }
}
