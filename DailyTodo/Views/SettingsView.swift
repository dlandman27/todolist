import SwiftUI
import UIKit

/// One pickable app icon. `iconName` is the alternate-icon asset name, nil for
/// the primary (Brick) icon. Mirrors the accent presets one-to-one (paired by
/// position with `ThemeStore.presets`, so `hex` links each icon to its accent);
/// previews are 128px copies of the real icons (IconPreview-<Name> imagesets).
private struct AppIconOption: Identifiable {
    let label: String
    let iconName: String?
    let hex: String
    var id: String { label }
    var previewName: String { "IconPreview-\(label)" }
}

private let appIconOptions: [AppIconOption] = {
    let names = ["Brick", "Red", "Sunset", "Gold", "Lime", "Forest", "Teal", "Cyan",
                 "Sky", "Ocean", "Indigo", "Grape", "Purple", "Magenta", "Pink",
                 "Rose", "Clay", "Slate"]
    return zip(names, ThemeStore.presets).map { name, hex in
        AppIconOption(label: name,
                      iconName: name == "Brick" ? nil : "AppIcon-\(name)",
                      hex: hex)
    }
}()

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
                        AppIconPickerView()
                    } label: {
                        Label("App Icon", systemImage: "app.badge.checkmark")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityIdentifier("appIcon")
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
}

/// Dedicated App Icon page, pushed from Settings — a labeled grid of every
/// accent-matched icon, kept off the main Settings page to avoid clutter.
struct AppIconPickerView: View {
    @Environment(ThemeModel.self) private var theme
    /// Mirrors UIApplication's alternate icon so the selection ring updates instantly.
    @State private var currentIconName: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(appIconOptions) { option in
                        VStack(spacing: 6) {
                            Image(option.previewName)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay {
                                    if currentIconName == option.iconName {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(Color.brand, lineWidth: 2)
                                            .padding(-3)
                                    }
                                }
                                // Quiet marker on the icon that matches the
                                // current accent, so it's findable while browsing.
                                .overlay(alignment: .bottomTrailing) {
                                    if option.hex == theme.accentHex {
                                        Circle()
                                            .fill(Color.brand)
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
                                            .offset(x: 4, y: 4)
                                    }
                                }
                            Text(option.label)
                                .font(.caption2)
                                .foregroundStyle(currentIconName == option.iconName
                                    ? Color.textPrimary : Color.textSecondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { setIcon(option) }
                        .accessibilityLabel("App icon \(option.label)")
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { currentIconName = UIApplication.shared.alternateIconName }
    }

    /// Swap the home-screen icon. iOS confirms the change with a system alert.
    private func setIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(option.iconName)
        currentIconName = option.iconName
        Haptics.selection()
    }
}
