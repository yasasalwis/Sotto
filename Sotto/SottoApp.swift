import SwiftData
import SwiftUI

@main
struct SottoApp: App {
    @State private var services: AppServices
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SottoAppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(SottoMacAppDelegate.self) private var appDelegate
    #endif

    init() {
        FontRegistrar.registerBundledFonts()
        let services = AppServices()
        _services = State(initialValue: services)
        #if os(iOS)
        SottoAppDelegate.services = services
        #else
        SottoMacAppDelegate.services = services
        #endif
    }

    #if os(macOS)
    /// Drives `MenuBarExtra`'s presence from the preference, so turning the status item off
    /// removes it without a relaunch.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { services.settings.showMenuBarExtra },
            set: { services.settings.showMenuBarExtra = $0 }
        )
    }
    #endif

    var body: some Scene {
        WindowGroup(id: WindowID.main) {
            RootView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: Theme.Layout.minimumWindowWidth, minHeight: Theme.Layout.minimumWindowHeight)
                // Route .gguf files and sotto:// links to the existing window instead of opening a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #endif
        }
        #if os(macOS)
        .handlesExternalEvents(matching: ["*"])
        #endif
        .commands {
            AppCommands(services: services)
        }
        .defaultSize(width: 1180, height: 760)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif

        #if os(macOS)
        Window("Model Library", id: WindowID.library) {
            ModelLibraryView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)

        Window("Compare", id: WindowID.compare) {
            CompareView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)

        Window("Tools", id: WindowID.tools) {
            ToolsView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)

        Window("Presets", id: WindowID.personas) {
            PersonasView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
        } label: {
            Image(systemName: "s.square")
                .accessibilityLabel("Sotto")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(width: 1180, height: 718)
        }
        #endif
    }
}

enum WindowID {
    static let main = "main"
    static let library = "library"
    static let compare = "compare"
    static let personas = "personas"
    static let tools = "tools"
}

#if os(iOS)
@MainActor
final class SottoAppDelegate: NSObject, UIApplicationDelegate {
    static weak var services: AppServices?

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        Self.services?.downloads.backgroundCompletionHandler = completionHandler
    }
}
#endif
