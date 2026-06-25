import SwiftUI

/// One stashed task: checkbox + title + a quiet relative return label.
struct StashRow: View {
    let task: TaskItem
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: TaskStyle.checkboxSymbol(done: task.done))
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            Text(task.title)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 8)

            Text(StashFormatting.returnLabel(for: task.stashReturnDate))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.appBackground)
    }
}
