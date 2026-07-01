import SwiftUI
import SwiftData

@main
struct DailyTodoApp: App {
    @State private var router = Router()
    @State private var live = LiveActivityController.shared
    @State private var midnight = MidnightScheduler()
    @State private var theme = ThemeModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system

    init() {
        // Opaque, seamless navigation bar: matches the app background with no hairline.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .appBackgroundColor
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    /// Clear completed tasks if a new day has started (catch-up on foreground / midnight).
    @MainActor
    private func runDailyCleanup() {
        DailyCleanup.runIfNeeded(in: TaskStore.shared.mainContext)
        StashReturn.runIfNeeded(in: TaskStore.shared.mainContext)
        RepeatSpawner.runIfNeeded(in: TaskStore.shared.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ListView()
                .environment(router)
                .environment(live)
                .environment(theme)
                .onOpenURL { url in
                    guard url.scheme == DeepLink.scheme else { return }
                    switch url.host {
                    case DeepLink.addHost: router.addRequested = true
                    case DeepLink.stashHost: router.stashRequested = true
                    default: break
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        runDailyCleanup()
                        live.refresh()
                        midnight.start { runDailyCleanup(); live.refresh() }
                    case .background, .inactive:
                        midnight.cancel()
                    @unknown default:
                        break
                    }
                }
                .task {
                    runDailyCleanup()
                    live.refresh()
                    midnight.start { runDailyCleanup(); live.refresh() }
                }
                .preferredColorScheme(appTheme.colorScheme)
        }
        .modelContainer(TaskStore.shared)
    }
}

/// Signals an add or stash request (e.g. from a deep link / Control Center control)
/// for the list to act on.
@Observable
final class Router {
    var addRequested = false
    var stashRequested = false
}
