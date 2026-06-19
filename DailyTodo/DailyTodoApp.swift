import SwiftUI
import SwiftData

@main
struct DailyTodoApp: App {
    @State private var router = Router()
    @State private var live = LiveActivityController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Opaque, seamless navigation bar: matches the app background with no hairline.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.appBackground)
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ListView()
                .environment(router)
                .environment(live)
                .onOpenURL { url in
                    if url.scheme == DeepLink.scheme, url.host == DeepLink.addHost {
                        router.addRequested = true
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { live.refresh() }
                }
                .task { live.refresh() }
        }
        .modelContainer(TaskStore.shared)
    }
}

/// Signals an add request (e.g. from the widget's deep link) for the list to act on.
@Observable
final class Router {
    var addRequested = false
}
