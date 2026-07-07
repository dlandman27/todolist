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
    /// Whether the edit card is shown. Mirrors focus, but is toggled inside an explicit
    /// `withAnimation` so the fade animates on every focus change, not just the first.
    @State private var cardVisible = false

    var body: some View {
        // First-baseline alignment keeps the checkbox on the first line when a
        // long title wraps, instead of floating at the row's vertical center.
        // While the field is empty it reports a bogus baseline that inflates the
        // row to two lines, so the empty draft aligns by center instead.
        HStack(alignment: task.title.isEmpty ? .center : .firstTextBaseline, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: TaskStyle.checkboxSymbol(done: task.done))
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.brand : Color.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: task.done)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle")
            .accessibilityLabel(task.done ? "Mark as not done" : "Mark as done")
            .accessibilityValue(task.done ? "done" : "open")

            // Vertical axis so long titles wrap instead of scrolling off-screen.
            // No built-in prompt: a vertical-axis field renders its placeholder on
            // an extra line while empty (the draft row showed two lines tall), so
            // the placeholder is drawn manually as an overlay instead.
            TextField("", text: $task.title, axis: .vertical)
                .overlay(alignment: .leading) {
                    if task.title.isEmpty {
                        Text("New to-do")
                            .foregroundStyle(Color.textSecondary.opacity(0.6))
                            .allowsHitTesting(false)
                    }
                }
                .focused(focus, equals: task.id)
                .strikethrough(task.done, color: .textSecondary)
                .foregroundStyle(task.done ? Color.textSecondary : Color.textPrimary)
                .submitLabel(.return)
                .accessibilityIdentifier("taskField")
                .onChange(of: focus.wrappedValue) { old, new in
                    if old == task.id && new != task.id { commit() }
                    // Drive the edit card with an explicit transaction. Relying on
                    // `.animation(value: isEditing)` only animated when the keyboard's
                    // first appearance supplied an ambient transaction — so the card
                    // faded on the first tap and snapped on every focus change after,
                    // once the keyboard was already up. `withAnimation` here always
                    // carries the transaction, regardless of keyboard state.
                    withAnimation(.appMotion) { cardVisible = (new == task.id) }
                }
                .onSubmit {
                    let hadText = !trimmed.isEmpty
                    commit()
                    if hadText { onReturn() }
                }
                // With a vertical axis the return key inserts a newline instead of
                // firing onSubmit — titles are single-line, so treat it as submit.
                .onChange(of: task.title) { _, new in
                    guard new.contains("\n") else { return }
                    task.title = new.replacingOccurrences(of: "\n", with: " ")
                    let hadText = !trimmed.isEmpty
                    commit()
                    if hadText { onReturn() }
                }
        }
        // Constant padding keeps the row height fixed in every state, so the only
        // thing that changes when editing is the card's opacity — and the card stays
        // within the row's own bounds (no negative padding) so the List cell never
        // clips its border.
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Make the whole row a tap target for editing, not just the text field — tapping
        // anywhere (except the checkbox, which keeps its own tap) focuses the field.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = task.id }
        // Card is always present and fades via `cardVisible`, which is toggled inside a
        // `withAnimation` block on focus change (see the TextField's `onChange`) rather
        // than via an implicit `.animation(value:)` — the latter only animated while
        // the keyboard happened to be transitioning.
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
        // Keep the card in sync if a row appears already focused (e.g. the freshly
        // added draft) without animating it in on scroll.
        .onAppear { cardVisible = isEditing }
        // Transparent so a custom background shows behind rows (ThemeBackground draws
        // appBackground itself when the kind is None — default look unchanged).
        .listRowBackground(Color.clear)
    }

    /// True while this row is the one being edited — drives the draft container styling.
    private var isEditing: Bool { focus.wrappedValue == task.id }

    private var trimmed: String {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle() {
        // No `withAnimation` here: the row move is animated declaratively by the
        // list (keyed on its layout signature), which animates consistently whether
        // the change arrives synchronously or via SwiftData's async republish.
        task.toggleDone()
        // Checking off feels like a completion; un-checking is a lighter tap.
        if task.done { Haptics.notify(.success) } else { Haptics.impact(.light) }
        try? context.save()
        LiveActivityController.shared.refresh()
        Surfaces.reload()
    }

    /// Trim the title; an empty row is discarded rather than left as a blank entry.
    private func commit() {
        task.title = trimmed
        if task.title.isEmpty {
            withAnimation(.appMotion) { context.delete(task) }
        }
        try? context.save()
        LiveActivityController.shared.refresh()
        Surfaces.reload()
    }
}
