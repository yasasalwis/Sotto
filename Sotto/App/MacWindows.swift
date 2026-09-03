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
}
#endif
