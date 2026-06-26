import SwiftUI
import SwiftData

/// One stashed task: checkbox + an editable title + a quiet relative return label.
/// Editing mirrors the main list's `TaskRow` — focus drives the field, and a row left
/// blank on commit is discarded.
struct StashRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    var focus: FocusState<UUID?>.Binding
    var onComplete: () -> Void
    /// Tapped the relative label → caller opens the re-snooze picker.
    var onResnoozeTap: () -> Void

    private var trimmed: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: TaskStyle.checkboxSymbol(done: task.done))
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            TextField("New stashed to-do", text: $task.title)
                .focused(focus, equals: task.id)
                .foregroundStyle(Color.textPrimary)
                .submitLabel(.done)
                .onChange(of: focus.wrappedValue) { old, new in
                    if old == task.id && new != task.id { commit() }
                }
                .onSubmit {
                    commit()
                    focus.wrappedValue = nil
                }

            Spacer(minLength: 8)

            Text(StashFormatting.returnLabel(for: task.stashReturnDate))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .contentShape(Rectangle())
                .onTapGesture { onResnoozeTap() }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.appBackground)
    }

    /// Trim the title; discard the row if it was left empty (a blank stashed draft).
    private func commit() {
        task.title = trimmed
        if task.title.isEmpty {
            context.delete(task)
        }
        try? context.save()
    }
}
