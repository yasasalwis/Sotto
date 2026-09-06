#if os(macOS)
import AppKit
import SwiftUI

/// The window `RootView` lives in, remembered so the menu bar item can bring it back.
///
/// With the menu bar item showing, Sotto keeps running after its window is closed
/// (`SottoMacAppDelegate`), and AppKit deallocates a closed window. A `weak` reference is
/// therefore exactly the signal wanted: `nil` means "there is no chat window, make one".
@MainActor
final class MainWindowRegistry {
    static let shared = MainWindowRegistry()

    weak var window: NSWindow?

    private init() {}
}

/// Records the window hosting the view it is attached to. Added to `RootView` as a
/// zero-sized background layer.
struct MainWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrackingView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// `viewDidMoveToWindow` is the point at which AppKit knows the window, which is later
    /// than `makeNSView` and fires again if the view is re-hosted in a new window.
    private final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainWindowRegistry.shared.window = window
        }
    }
}

enum MainWindow {
    /// Brings the chat window forward, re-creating it when it was closed while Sotto stayed
    /// resident in the menu bar.
    @MainActor
    static func show(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        if let window = MainWindowRegistry.shared.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: WindowID.main)
        }
    }
}

/// Keeps Sotto alive when its last window closes, so the menu bar item still has an app
/// behind it. Without the menu bar item there would be no way back other than the Dock, so
/// in that case the app quits the way a document-less app normally does.
@MainActor
final class SottoMacAppDelegate: NSObject, NSApplicationDelegate {
    static weak var services: AppServices?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.services?.settings.showMenuBarExtra != true
    }

    /// Clicking the Dock icon after the window was closed brings a window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    #if DEBUG
    /// Gives a test-launched app the external event its main scene is waiting for.
    ///
    /// `WindowGroup` here carries `.handlesExternalEvents(matching: ["*"])`, which makes SwiftUI
    /// defer creating a window until an external event arrives. Finder, the Dock, Spotlight and
    /// `open` all send one, so every real launch gets a window — but XCUITest execs the binary
    /// directly and sends nothing, so the app came up with a menu bar and no window and all three
    /// `SottoUITests` timed out hunting for views that were never on screen. That is a harness
    /// mismatch, not a defect a user can reach, and it had quietly disabled the only test covering
    /// the sandboxed export.
    ///
    /// Re-opening our own bundle sends exactly the event the scene wants, at the one moment it is
    /// missing. Gated on a launch argument only the UI tests pass, and compiled out of Release.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "uiTesting") else { return }
        NSWorkspace.shared.open(Bundle.main.bundleURL)
    }
    #endif
}
#endif
