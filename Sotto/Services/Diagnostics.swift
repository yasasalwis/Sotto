import Foundation
import MetricKit
import os

/// Opt-in crash and hang diagnostics. Nothing is transmitted anywhere; reports are written
/// to the app container and the user can review, share or delete them.
@MainActor
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber {
    let directory: URL
    private var subscribed = false

    init(directory: URL) {
        self.directory = directory
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !subscribed {
            MXMetricManager.shared.add(self)
            subscribed = true
            Log.privacy.info("Diagnostics collection enabled (local only)")
        } else if !enabled, subscribed {
            MXMetricManager.shared.remove(self)
            subscribed = false
            Log.privacy.info("Diagnostics collection disabled")
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let directory = self.directory
        let blobs = payloads.map { ($0.timeStampEnd, $0.jsonRepresentation()) }
        Task { @MainActor in
            for (date, data) in blobs {
                let name = "diagnostic-\(Int(date.timeIntervalSince1970)).json"
                try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // Aggregate metrics are not collected; only diagnostics the user opted into.
    }

    func reports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func deleteAllReports() {
        for url in reports() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
