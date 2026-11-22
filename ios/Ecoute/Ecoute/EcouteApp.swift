import SwiftUI

enum AppTab: Hashable { case listen, library }

/// Les pages de la bibliothèque.
enum LibRoute: Hashable {
    case category(String)
    case doc(UUID)
    case part(UUID, UUID)   // enregistrement, partie
}

@MainActor
final class AppNav: ObservableObject {
    @Published var tab: AppTab = .listen
    @Published var libraryPath: [LibRoute] = []
}

@main
struct EcouteApp: App {
    @StateObject private var store: Store
    @StateObject private var settings: Settings
    @StateObject private var engine: Engine
    @StateObject private var nav = AppNav()

    init() {
        let store = Store()
        let settings = Settings()
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _engine = StateObject(wrappedValue: Engine(store: store, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(nav)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var nav: AppNav
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView(selection: $nav.tab) {
            ListenView()
                .tabItem { Label("Écoute", systemImage: engine.isLive ? "record.circle.fill" : "mic") }
                .tag(AppTab.listen)
            LibraryView()
                .tabItem { Label("Bibliothèque", systemImage: "books.vertical") }
                .tag(AppTab.library)
        }
        .overlay(alignment: .bottom) {
            if let text = engine.banner {
                BannerView(text: text).padding(.bottom, 64).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.banner)
        // L'enregistrement terminé s'ouvre tout seul.
        .onChange(of: engine.finishedDocId) { _, id in
            guard let id else { return }
            nav.tab = .library
            nav.libraryPath = [.doc(id)]
            engine.finishedDocId = nil
        }
        .onChange(of: phase) { _, p in if p != .active { store.saveNow() } }
    }
}
