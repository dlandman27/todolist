import SwiftUI
import PhotosUI

/// Dedicated "make it yours" screen, pushed from Settings → Appearance → Customize.
/// Hosts the accent and background; app icons land here next.
struct CustomizeView: View {
    @Environment(ThemeModel.self) private var theme
    @Environment(LiveActivityController.self) private var live
    @State private var photoItem: PhotosPickerItem?

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Form {
                Section {
                    previewTile
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background {
                            ThemeBackground()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("Preview")
                }

                Section {
                    LazyVGrid(columns: swatchColumns, spacing: 12) {
                        ForEach(ThemeStore.presets, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: ThemeStore.hexValue(hex)))
                                .frame(height: 34)
                                .overlay {
                                    if theme.accentHex == hex {
                                        Circle().stroke(Color.textPrimary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .contentShape(Circle())
                                .onTapGesture { setAccent(hex) }
                                .accessibilityIdentifier("accent-\(hex)")
                                .accessibilityLabel("Accent \(hex)")
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.appSurface)

                    ColorPicker(selection: accentBinding, supportsOpacity: false) {
                        Label("Custom", systemImage: "eyedropper")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .listRowBackground(Color.appSurface)
                } header: {
                    Text("Accent")
                } footer: {
                    Text("Sets the highlight color across the app, widget, and Live Activity.")
                }

                Section {
                    Picker("Background", selection: backgroundKindBinding) {
                        ForEach(BackgroundKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.appSurface)

                    switch theme.backgroundKind {
                    case .none:
                        EmptyView()
                    case .solid:
                        ColorPicker(selection: solidBinding, supportsOpacity: false) {
                            Label("Color", systemImage: "paintpalette")
                                .foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                    case .gradient:
                        ColorPicker(selection: gradientTopBinding, supportsOpacity: false) {
                            Label("Top", systemImage: "arrow.up").foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                        ColorPicker(selection: gradientBottomBinding, supportsOpacity: false) {
                            Label("Bottom", systemImage: "arrow.down").foregroundStyle(Color.textPrimary)
                        }
                        .listRowBackground(Color.appSurface)
                    case .photo:
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(theme.backgroundImage == nil ? "Choose Photo" : "Change Photo",
                                  systemImage: "photo")
                                .foregroundStyle(Color.brand)
                        }
                        .listRowBackground(Color.appSurface)
                        if theme.backgroundImage != nil {
                            Button(role: .destructive) { theme.clearPhoto() } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                            .listRowBackground(Color.appSurface)
                        }
                    }
                } header: {
                    Text("Background")
                } footer: {
                    Text("Applies to the main list and stash. Photos stay on your device.")
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            theme.setPhoto(data)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// A small mock list that recolors live as the accent changes.
    private var previewTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Todo").font(.headline).foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.brand)
            }
            previewRow("Buy groceries", done: false)
            previewRow("Call dentist", done: true)
        }
        .padding(.vertical, 6)
    }

    private func previewRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.brand : Color.textSecondary)
            Text(title)
                .foregroundStyle(done ? Color.textSecondary : Color.textPrimary)
                .strikethrough(done)
            Spacer()
        }
    }

    /// Two-way bridge between the live accent and SwiftUI's ColorPicker.
    private var accentBinding: Binding<Color> {
        Binding(get: { theme.accent }, set: { setAccent($0.toHex()) })
    }

    /// Update the accent live (model), persist it, and push it to every surface.
    private func setAccent(_ hex: String) {
        theme.setAccent(hex)
        Haptics.selection()
        Surfaces.reload()
        live.refresh()
    }

    // MARK: Background bindings

    private var backgroundKindBinding: Binding<BackgroundKind> {
        Binding(get: { theme.backgroundKind }, set: { theme.setBackgroundKind($0) })
    }
    private var solidBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.backgroundColorHex)) },
                set: { theme.setSolid($0.toHex()) })
    }
    private var gradientTopBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.gradientTopHex)) },
                set: { theme.setGradient(top: $0.toHex(), bottom: theme.gradientBottomHex) })
    }
    private var gradientBottomBinding: Binding<Color> {
        Binding(get: { Color(hex: ThemeStore.hexValue(theme.gradientBottomHex)) },
                set: { theme.setGradient(top: theme.gradientTopHex, bottom: $0.toHex()) })
    }
}
