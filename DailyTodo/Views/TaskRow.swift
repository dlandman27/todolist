import SwiftUI
import SwiftData
import WidgetKit

/// A single task. Tap the circle to toggle done; tap the text to edit it in place.
/// Editing is driven by the parent's focus state so a freshly-added row opens ready to type.
struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskItem
    var focus: FocusState<UUID?>.Binding
    /// Called when Return is pressed on a non-empty row, to chain into a new one.
    var onReturn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.brand : Color.textSecondary)
            }
            .buttonStyle(.plain)

            TextField("New to-do", text: $task.title)
                .focused(focus, equals: task.id)
                .strikethrough(task.done, color: .textSecondary)
                .foregroundStyle(task.done ? Color.textSecondary : Color.textPrimary)
                .submitLabel(.return)
                .onChange(of: focus.wrappedValue) { old, new in
                    if old == task.id && new != task.id { commit() }
                }
                .onSubmit {
                    let hadText = !trimmed.isEmpty
                    commit()
                    if hadText { onReturn() }
                }

            if task.done, let completedAt = task.completedAt {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    Text(completedLabel(completedAt))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .listRowBackground(Color.appBackground)
    }

    private var trimmed: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Today shows the time it was checked off; earlier days show the date.
    private func completedLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func toggle() {
        withAnimation {
            task.toggleDone()
        }
        try? context.save()
        LiveActivityController.shared.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Trim the title; an empty row is discarded rather than left as a blank entry.
    private func commit() {
        task.title = trimmed
        if task.title.isEmpty {
            context.delete(task)
        }
        try? context.save()
        LiveActivityController.shared.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
