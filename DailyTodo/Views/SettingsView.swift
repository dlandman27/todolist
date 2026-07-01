import SwiftUI

/// App settings. Pushed onto the list's navigation stack from the title-bar gear.
/// Currently just haptics, but structured as a grouped form so it can grow.
struct SettingsView: View {
    @AppStorage(Haptics.defaultsKey) private var hapticsEnabled = true
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @AppStorage(DailyCleanup.enabledKey, store: AppGroup.defaults) private var autoClearEnabled = true

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
                } footer: {
                    Text("Accent color, and soon backgrounds and app icons.")
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
