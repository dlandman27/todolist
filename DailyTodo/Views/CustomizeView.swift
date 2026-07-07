import SwiftUI
import PhotosUI
struct CustomizeView: View {
    @Environment(ThemeModel.self) private var theme
    @Environment(LiveActivityController.self) private var live
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Customize")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    caption("Accent")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemeStore.presets, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: ThemeStore.hexValue(hex)))
                                    .frame(width: 36, height: 36)
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
                        // Breathing room so the selection ring isn't clipped.
                        .padding(4)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    caption("Background")
                    Picker("Background", selection: backgroundKindBinding) {
                        ForEach(BackgroundKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if theme.backgroundKind == .solid {
                        // Accent-matched solid presets, light tints through deep
                        // darks — recomputed live from the current accent, so a
                        // new accent immediately offers backgrounds that fit it.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(solidPresets, id: \.self) { hex in
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: ThemeStore.hexValue(hex)))
                                        .frame(width: 64, height: 40)
                                        .overlay {
                                            // Faint edge so near-white tints don't vanish.
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.textSecondary.opacity(0.25), lineWidth: 1)
                                        }
                                        .overlay {
                                            if theme.backgroundColorHex == hex {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(Color.textPrimary, lineWidth: 2)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            theme.setSolid(hex)
                                            Haptics.selection()
                                        }
                                        .accessibilityLabel("Background \(hex)")
                                }
                            }
                            .padding(2)
                        }
                    }

                    if theme.backgroundKind == .gradient {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ThemeStore.gradientPresets) { preset in
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(preset.gradient)
                                        .frame(width: 64, height: 40)
                                        .overlay {
                                            if theme.gradientTopHex == preset.top && theme.gradientBottomHex == preset.bottom {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(Color.textPrimary, lineWidth: 2)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture { theme.setGradient(top: preset.top, bottom: preset.bottom) }
                                        .accessibilityLabel("Gradient \(preset.id)")
                                }
                            }
                            .padding(2)
                        }
                    }

                    if theme.backgroundKind != .none {
                        // The labeled option rows live in a grouped card, styled
                        // like Settings cells.
                        VStack(spacing: 0) {
                            switch theme.backgroundKind {
                            case .none:
                                EmptyView()
                            case .solid:
                                optionRow {
                                    ColorPicker(selection: solidBinding, supportsOpacity: false) {
                                        Text("Color").foregroundStyle(Color.textPrimary)
                                    }
                                }
                            case .gradient:
                                optionRow {
                                    // Side by side, not stacked — height is scarce here.
                                    HStack(spacing: 16) {
                                        ColorPicker(selection: gradientTopBinding, supportsOpacity: false) {
                                            Text("Top").foregroundStyle(Color.textPrimary)
                                        }
                                        ColorPicker(selection: gradientBottomBinding, supportsOpacity: false) {
                                            Text("Bottom").foregroundStyle(Color.textPrimary)
                                        }
                                        Button {
                                            theme.setGradient(top: theme.gradientBottomHex, bottom: theme.gradientTopHex)
                                            Haptics.selection()
                                        } label: {
                                            Image(systemName: "arrow.up.arrow.down.circle")
                                                .font(.title3)
                                                .foregroundStyle(Color.brand)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Swap top and bottom colors")
                                    }
                                }
                            case .photo:
                                optionRow {
                                    HStack {
                                        PhotosPicker(selection: $photoItem, matching: .images) {
                                            Label(theme.backgroundImage == nil ? "Choose Photo" : "Change Photo",
                                                  systemImage: "photo")
                                                .foregroundStyle(Color.brand)
                                        }
                                        Spacer()
                                        if theme.backgroundImage != nil {
                                            Button(role: .destructive) { theme.clearPhoto() } label: {
                                                Label("Remove", systemImage: "trash")
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                    }
                                }
                            }

                            Divider()
                                .padding(.leading, 16)

                            optionRow {
                                Toggle(isOn: showOnWidgetBinding) {
                                    Text("Show on Widget").foregroundStyle(Color.textPrimary)
                                }
                                .tint(Color.brand)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.appSurface)
                        )
                    }
                }
            }
            .padding(20)
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

    /// One grouped-card row: the same padding rhythm as a Settings cell.
    private func optionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    /// Solid background presets: the app's own neutral backgrounds (FFF9FB
    /// light / 171113 dark) with a little accent blended IN — so they read as
    /// "the default, leaned toward your color", not a saturated wall of it.
    /// Two light tints, then three dark shades of increasing tint strength.
    private var solidPresets: [String] {
        let accent = theme.accentHex
        return [
            blend(accent, into: "FFF9FB", amount: 0.10),
            blend(accent, into: "FFF9FB", amount: 0.22),
            blend(accent, into: "171113", amount: 0.12),
            blend(accent, into: "171113", amount: 0.25),
            blend(accent, into: "171113", amount: 0.40),
        ]
    }

    /// Tint `base` with `amount` of the accent, per RGB channel.
    private func blend(_ accentHex: String, into baseHex: String, amount: Double) -> String {
        let accent = ThemeStore.hexValue(accentHex)
        let base = ThemeStore.hexValue(baseHex)
        func channel(_ shift: UInt32) -> Int {
            let a = Double((accent >> shift) & 0xFF)
            let b = Double((base >> shift) & 0xFF)
            return Int((b + (a - b) * amount).rounded())
        }
        return String(format: "%02X%02X%02X", channel(16), channel(8), channel(0))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
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
    private var showOnWidgetBinding: Binding<Bool> {
        Binding(get: { theme.showBackgroundOnWidget }, set: { theme.setShowBackgroundOnWidget($0) })
    }
}
