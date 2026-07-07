import SwiftUI
import SwiftData

/// Card-modal detail page for one task, opened from the info button on a
/// focused row. Edits land on local copies and only apply on the check —
/// the X (or a swipe-down) asks before discarding actual changes.
struct TaskDetailView: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title: String
    @State private var notes: String
    @State private var showDiscardConfirm = false

    init(task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
    }

    /// Anything actually different from what's stored?
    private var hasChanges: Bool {
        title != task.title || notes != task.notes
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Task name", text: $title, axis: .vertical)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                        .padding(14)
                        .background(card)
                        .accessibilityIdentifier("detailTitle")

                    // TextEditor has no placeholder of its own — overlay one.
                    TextEditor(text: $notes)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 180, maxHeight: 320)
                        .background(card)
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty {
                                Text("Notes")
                                    .foregroundStyle(Color.textSecondary.opacity(0.6))
                                    .padding(.top, 17)
                                    .padding(.leading, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("detailNotes")

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if hasChanges {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Save")
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .tint(Color.brand)
        // A casual swipe-down shouldn't silently eat edits — block it while
        // there are unsaved changes (the X then offers the discard choice).
        .interactiveDismissDisabled(hasChanges)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.appSurface)
    }

    /// Apply the local edits and close. Never deletes here — this sheet is
    /// presented BY the task's own row, and removing that row mid-dismissal
    /// wedges the presentation and strands the list's focus. A title cleared
    /// to nothing just leaves a blank draft, which the row's blur-commit
    /// already cleans up.
    private func save() {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes
        try? context.save()
        Haptics.selection()
        LiveActivityController.shared.refresh()
        Surfaces.reload()
        dismiss()
    }
}
