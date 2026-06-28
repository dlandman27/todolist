import SwiftUI

/// Transient bottom toast shown after a removal, offering a one-tap Undo. Swipe it
/// downward to dismiss. Purely presentational — the caller owns when it appears and
/// auto-dismisses.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    var onDismiss: () -> Void = {}

    /// Downward drag distance (clamped to ≥ 0) tracking the dismiss gesture.
    @State private var dragOffset: CGFloat = 0

    /// Drag past this many points down to dismiss; shorter drags spring back.
    private let dismissThreshold: CGFloat = 40

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 12)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(
            Capsule()
                .fill(Color.appSurface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .padding(.horizontal)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > dismissThreshold {
                        onDismiss()
                    } else {
                        withAnimation(.appMotion) { dragOffset = 0 }
                    }
                }
        )
    }
}

/// A transient status toast (no action button) — e.g. confirming the Live Activity
/// was turned on/off. Swipe it downward to dismiss, mirroring `UndoToast`. Caller
/// owns when it appears and auto-dismisses.
struct InfoToast: View {
    let message: String
    var onDismiss: () -> Void = {}

    /// Downward drag distance (clamped to ≥ 0) tracking the dismiss gesture.
    @State private var dragOffset: CGFloat = 0

    /// Drag past this many points down to dismiss; shorter drags spring back.
    private let dismissThreshold: CGFloat = 40

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.appSurface)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            )
            .padding(.horizontal, 24)
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            onDismiss()
                        } else {
                            withAnimation(.appMotion) { dragOffset = 0 }
                        }
                    }
            )
    }
}

#Preview {
    UndoToast(message: "Removed 5 tasks", onUndo: {})
}

#Preview {
    InfoToast(message: "You're now live. Tasks will show in your Live Activities.")
}
