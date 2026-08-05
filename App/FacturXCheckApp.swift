import SwiftUI

@main
struct FacturXCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var inspection = Inspection()
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(inspection)
                .preferredColorScheme(appearance.colorScheme)
                .task { delegate.adopt(inspection) }
        }
        .defaultSize(width: 1160, height: 720)
        .commands {
            // Un outil qui n'ouvre rien d'autre que des PDF n'a pas besoin
            // d'un menu Nouveau document.
            CommandGroup(replacing: .newItem) { }
        }

        // La scène `Settings` donne d'un coup l'entrée dans le menu de
        // l'application, le raccourci ⌘, et une vraie fenêtre indépendante.
        Settings {
            SettingsView()
        }
    }
}

/// Reçoit les fichiers ouverts depuis le Finder — double-clic, « Ouvrir
/// avec », ou dépôt sur l'icône du Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inspection: Inspection?
    /// Ouvrir un PDF alors que l'application est fermée la lance : le Finder
    /// livre alors les fichiers avant que la fenêtre n'existe. Sans cette
    /// file d'attente, ce sont précisément ces fichiers-là qu'on perdrait.
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let inspection {
            inspection.add(urls)
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func adopt(_ inspection: Inspection) {
        guard self.inspection == nil else { return }
        self.inspection = inspection
        if !pending.isEmpty {
            inspection.add(pending)
            pending.removeAll()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
