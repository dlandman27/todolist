import SwiftUI
import UIKit

/// App settings. Pushed onto the list's navigation stack from the title-bar gear.
/// Currently just haptics, but structured as a grouped form so it can grow.
struct SettingsView: View {
    @Environment(LiveActivityController.self) private var live
    @AppStorage(Haptics.defaultsKey) private var hapticsEnabled = true
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @AppStorage(DailyCleanup.enabledKey, store: AppGroup.defaults) private var autoClearEnabled = true
    @AppStorage(LiveActivityController.enabledKey, store: AppGroup.defaults) private var liveActivityEnabled = true

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Form {
                Section {
                    Picker(selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    } label: {
                        Label("App Theme", systemImage: "circle.lefthalf.filled")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brand)
                    .listRowBackground(Color.appSurface)

                    NavigationLink {
                        CustomizeView()
                    } label: {
                        Label("Customize", systemImage: "paintbrush")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityIdentifier("customize")
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle(isOn: $autoClearEnabled) {
                        Label("Clear Completed at End of Day", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brand)
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("End of Day")
                } footer: {
                    Text("Automatically remove completed tasks at midnight. Unfinished tasks carry over.")
                }

                Section {
                    NavigationLink {
                        RepeatingRulesView()
                    } label: {
                        Label("Repeating Tasks", systemImage: "repeat")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityIdentifier("repeatingTasks")
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Repeating")
                } footer: {
                    Text("Set up to-dos that get added automatically every week or month.")
                }

                Section {
                    if live.systemEnabled {
                        Toggle(isOn: $liveActivityEnabled) {
                            Label("Show on Lock Screen", systemImage: "lock.iphone")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .tint(Color.brand)
                        .listRowBackground(Color.appSurface)
                        // The toggle owns the preference (via AppStorage); this kicks
                        // the controller so the activity starts or ends immediately.
                        .onChange(of: liveActivityEnabled) { _, on in
                            on ? live.start() : live.stop()
                        }
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Enable Live Activities in iOS Settings", systemImage: "lock.iphone")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                    }
                } header: {
                    Text("Lock Screen")
                } footer: {
                    Text(live.systemEnabled
                        ? "Keep your list pinned to the Lock Screen as a Live Activity. It updates automatically as you check things off."
                        : "Live Activities are turned off for this app in iOS Settings.")
                }

                Section {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .tint(Color.brand)
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Play a subtle vibration when you add, complete, or delete tasks.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
