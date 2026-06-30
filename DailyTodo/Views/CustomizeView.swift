import SwiftUI

/// Dedicated "make it yours" screen, pushed from Settings → Appearance → Customize.
/// Hosts the accent now; backgrounds (Spec 2) and app icons land here next.
struct CustomizeView: View {
    @Environment(ThemeModel.self) private var theme
    @Environment(LiveActivityController.self) private var live

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Form {
                Section {
                    previewTile.listRowBackground(Color.appSurface)
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
}
