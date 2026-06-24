import SwiftUI

/// Transient bottom toast shown after a bulk clear, offering a one-tap Undo.
/// Purely presentational — the caller owns when it appears and auto-dismisses.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

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
    }
}

#Preview {
    UndoToast(message: "Cleared 5 tasks", onUndo: {})
}
