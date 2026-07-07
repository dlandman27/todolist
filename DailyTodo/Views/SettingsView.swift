import SwiftUI
import UIKit

/// One pickable app icon. `iconName` is the alternate-icon asset name, nil for
/// the primary (Brick) icon. Mirrors the accent presets one-to-one; previews
/// are 128px copies of the real icons (IconPreview-<Name> imagesets).
private struct AppIconOption: Identifiable {
    let label: String
    let iconName: String?
    var id: String { label }
    var previewName: String { "IconPreview-\(label)" }
}

private let appIconOptions: [AppIconOption] =
    [AppIconOption(label: "Brick", iconName: nil)] +
    ["Red", "Sunset", "Gold", "Lime", "Forest", "Teal", "Cyan", "Sky", "Ocean",
     "Indigo", "Grape", "Purple", "Magenta", "Pink", "Rose", "Clay", "Slate"]
        .map { AppIconOption(label: $0, iconName: "AppIcon-\($0)") }

/// App settings. Pushed onto the list's navigation stack from the title-bar gear.
/// Currently just haptics, but structured as a grouped form so it can grow.
struct SettingsView: View {
    @Environment(LiveActivityController.self) private var live
    @Environment(ThemeModel.self) private var theme
    @AppStorage(Haptics.defaultsKey) private var hapticsEnabled = true
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @AppStorage(DailyCleanup.enabledKey, store: AppGroup.defaults) private var autoClearEnabled = true
    @AppStorage(LiveActivityController.enabledKey, store: AppGroup.defaults) private var liveActivityEnabled = true
    @State private var showCustomize = false
    /// Mirrors UIApplication's alternate icon so the selection ring updates instantly.
    @State private var currentIconName: String?

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

                    Button {
                        showCustomize = true
                    } label: {
                        Label("Customize", systemImage: "paintbrush")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityIdentifier("customizeFromSettings")
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Appearance")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(appIconOptions) { option in
                                Image(option.previewName)
                                    .resizable()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .overlay {
                                        if currentIconName == option.iconName {
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .stroke(Color.brand, lineWidth: 2)
                                                .padding(-3)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { setIcon(option) }
                                    .accessibilityLabel("App icon \(option.label)")
                            }
                        }
                        .padding(4)
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("Changes the icon on your Home Screen.")
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
        // Same live-preview sheet the ellipsis menu opens — Settings itself
        // recolors behind it as changes land.
        .onAppear { currentIconName = UIApplication.shared.alternateIconName }
        .sheet(isPresented: $showCustomize) {
            CustomizeView()
                .environment(theme)
                .environment(live)
                .presentationDetents([.height(380), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Swap the home-screen icon. iOS confirms the change with a system alert.
    private func setIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(option.iconName)
        currentIconName = option.iconName
        Haptics.selection()
    }
}
