import SwiftData
import SwiftUI

@main
struct SottoApp: App {
    @State private var services: AppServices
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SottoAppDelegate.self) private var appDelegate
    #endif

    init() {
        FontRegistrar.registerBundledFonts()
        let services = AppServices()
        _services = State(initialValue: services)
        #if os(iOS)
        SottoAppDelegate.services = services
        #endif
    }

    var body: some Scene {
        WindowGroup {
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

        Window("Presets", id: WindowID.personas) {
            PersonasView()
                .environment(services)
                .modelContainer(services.container)
                .preferredColorScheme(.light)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)

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
    static let library = "library"
    static let compare = "compare"
    static let personas = "personas"
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
