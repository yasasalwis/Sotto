import CoreText
import Foundation
import os

/// Registers the bundled Geist and IBM Plex Mono faces with CoreText at launch so
/// `Font.custom` resolves them on every platform without Info.plist font lists.
enum FontRegistrar {
    private static let logger = Logger(subsystem: "lk.eonix.sotto", category: "fonts")
    private static var registered = false

    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        guard !urls.isEmpty else {
            logger.error("No bundled fonts found; falling back to system faces")
            return
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let description = error?.takeRetainedValue().localizedDescription ?? "unknown error"
                logger.error("Font registration failed for \(url.lastPathComponent, privacy: .public): \(description, privacy: .public)")
            }
        }
    }
}
