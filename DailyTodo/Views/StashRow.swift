import SwiftUI
import SwiftData

/// One stashed task: checkbox + an editable title + a quiet relative return label.
/// Editing mirrors the main list's `TaskRow` — focus drives the field and the edit
/// card, and a row left blank on commit is discarded.
struct StashRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    var focus: FocusState<UUID?>.Binding
    var onComplete: () -> Void
    /// Tapped the relative label → caller opens the re-snooze picker.
    var onResnoozeTap: () -> Void

    /// Whether the edit card is shown — mirrors focus, toggled in a `withAnimation` so it
    /// fades on every focus change (matching `TaskRow`).
    @State private var cardVisible = false

    private var isEditing: Bool { focus.wrappedValue == task.id }
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
                    withAnimation(.appMotion) { cardVisible = (new == task.id) }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.brand.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.brand.opacity(0.12), radius: 8, y: 2)
                .opacity(cardVisible ? 1 : 0)
        }
        .onAppear { cardVisible = isEditing }
        .listRowBackground(Color.clear)
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
