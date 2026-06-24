import SwiftUI
import SwiftData
import WidgetKit

/// The whole app: one running list you add to inline, check off, edit, and delete.
struct ListView: View {
    @Environment(Router.self) private var router
    @Environment(LiveActivityController.self) private var live
    @Environment(\.modelContext) private var context
    @FocusState private var focusedTask: UUID?
    @AppStorage(ListSettings.nameKey, store: AppGroup.defaults) private var listName = ListSettings.defaultName
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool
    @State private var showClearAllConfirm = false
    @State private var showClearCompletedConfirm = false
    @State private var pendingUndo: PendingUndo?
    @Environment(\.scenePhase) private var scenePhase

    /// Tasks removed within the current undo window, accumulated across deletes and
    /// clears, held in memory only while the toast is up. `id` changes on every new
    /// removal so the auto-dismiss timer restarts (a rolling 5s window).
    private struct PendingUndo {
        let id = UUID()
        let snapshots: [TaskSnapshot]
        var message: String { "Removed \(snapshots.count) task\(snapshots.count == 1 ? "" : "s")" }
    }

    @Query(sort: \TaskItem.createdAt, order: .forward) private var tasks: [TaskItem]

    /// Open tasks first, completed ones sunk to the bottom in check-off order.
    private var orderedTasks: [TaskItem] { TaskOrdering.ordered(tasks) }

    /// A signature of the displayed order and each row's done-state. Driving the
    /// list's animation off this value (rather than a per-tap `withAnimation`) means
    /// a row move animates consistently no matter which path delivers the change —
    /// the synchronous edit or SwiftData's later async `@Query` republish. Those two
    /// paths used to race, so completing a task animated only intermittently.
    private var layoutSignature: [String] {
        orderedTasks.map { "\($0.id)|\($0.done)" }
    }

    /// True while either a task row or the title is being edited — a tap off should
    /// then just unfocus, never add a new task.
    private var isEditing: Bool { focusedTask != nil || titleFocused }

    /// Number of checked-off tasks — gates the "Clear Completed" item and labels its dialog.
    private var completedCount: Int { tasks.filter(\.done).count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Tapping empty chrome (header, sides) only dismisses an active edit —
                    // it must NOT add a task. Adding is handled by the explicit areas below.
                    .onTapGesture { dismissEditing() }
                VStack(spacing: 0) {
                    titleHeader
                    if tasks.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        list
                            .transition(.opacity)
                    }
                }
                // Cross-fade between the list and the empty state on any path to/from
                // empty (clear, last row deleted, discarded draft).
                .animation(.appMotion, value: tasks.isEmpty)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let pending = pendingUndo {
                        UndoToast(message: pending.message, onUndo: undo, onDismiss: dismissUndo)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    liveActivityButton
                }
                .animation(.appMotion, value: pendingUndo?.id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Delete all \(tasks.count) tasks?",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete \(completedCount) completed task\(completedCount == 1 ? "" : "s")?",
                isPresented: $showClearCompletedConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Completed", role: .destructive) { clearCompleted() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onChange(of: router.addRequested) { _, requested in
            if requested {
                addTask()
                router.addRequested = false
            }
        }
        .task(id: pendingUndo?.id) {
            guard pendingUndo != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.appMotion) { pendingUndo = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingUndo = nil }
        }
    }

    /// The app's title — double-tap to rename the list — with the settings gear trailing.
    private var titleHeader: some View {
        HStack(alignment: .center) {
            if editingTitle {
                TextField(ListSettings.defaultName, text: $listName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.textPrimary)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(finishEditingTitle)
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { finishEditingTitle() }
                    }
                    .onChange(of: listName) { _, new in
                        if new.count > ListSettings.maxNameLength {
                            listName = String(new.prefix(ListSettings.maxNameLength))
                        }
                    }
                    .accessibilityIdentifier("title")
            } else {
                Text(listName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityIdentifier("title")
                    .onTapGesture(count: 2, perform: beginEditingTitle)
            }
            Spacer()
            HStack(spacing: 8) {
                listOptionsButton
                settingsButton
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Enter rename mode and drop the cursor into the title field.
    private func beginEditingTitle() {
        editingTitle = true
        // Defer focus until the field is in the hierarchy.
        DispatchQueue.main.async { titleFocused = true }
    }

    /// Commit the rename: trim, fall back to the default if blank, and push the new
    /// name out to the Lock Screen and widgets.
    private func finishEditingTitle() {
        let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        listName = trimmed.isEmpty ? ListSettings.defaultName : trimmed
        editingTitle = false
        titleFocused = false
        Haptics.selection()
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The ⋯ list-options menu: bulk actions on this list. Sections keep room for a
    /// future "Sort By" section without adding another header button.
    private var listOptionsButton: some View {
        Menu {
            Section {
                Button {
                    showClearCompletedConfirm = true
                } label: {
                    Label("Clear Completed", systemImage: "checkmark.circle.badge.xmark")
                }
                .disabled(completedCount == 0)

                Button(role: .destructive) {
                    showClearAllConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(tasks.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("listOptions")
        .accessibilityLabel("List options")
    }

    /// Gear that pushes the settings page onto the navigation stack.
    private var settingsButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "gearshape")
                .font(.title2)
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settings")
        .accessibilityLabel("Settings")
    }

    /// Bottom control to pin the list to the Lock Screen as a Live Activity.
    @ViewBuilder
    private var liveActivityButton: some View {
        if !live.systemEnabled {
            Label("Turn on Live Activities in Settings", systemImage: "lock.slash")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 8)
        } else {
            Button {
                Haptics.impact(.medium)
                withAnimation(.snappy) { live.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if live.isRunning {
                        LiveDot()
                    } else {
                        Circle()
                            .stroke(Color.textSecondary, lineWidth: 1.5)
                            .frame(width: 9, height: 9)
                    }
                    Text(live.isRunning ? "Live" : "Go Live")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.brand)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .glassCapsule(tinted: live.isRunning)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private var list: some View {
        // GeometryReader so the tap-to-add area can fill the full viewport height —
        // a fixed height leaves dead, non-tappable List background below it on tall screens.
        GeometryReader { geo in
            List {
                ForEach(orderedTasks) { task in
                    TaskRow(task: task, focus: $focusedTask, onReturn: addTask)
                        .listRowSeparator(.hidden)
                        // Override List's chunky default row insets. Leading 4 + the row's
                        // own 12pt content padding = 16, lining the checkbox up with the
                        // "Todo" title; tight top/bottom keeps rows close together.
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        // Completed rows are locked below the open group; the blank
                        // draft can't be dragged mid-edit.
                        .moveDisabled(task.done || task.isBlank)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                // The empty space below the list is a reliable tap target (a Button, not a
                // row gesture): dismiss an open draft, otherwise add a task.
                Button {
                    if isEditing { dismissEditing() } else { addTask() }
                } label: {
                    Color.clear
                        .frame(minHeight: addAreaHeight(viewport: geo.size.height))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.appBackground)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            // Default min row height (44) leaves single-line rows looking spaced out;
            // shrink it so rows hug their content.
            .environment(\.defaultMinListRowHeight, 36)
            .animation(.appMotion, value: layoutSignature)
        }
    }

    /// Height for the tap-to-add area below the rows: fills the space left under the
    /// rows (so it's all tappable) without adding scroll overflow. Rows are ~56pt; the
    /// floor keeps a usable tap target once the list nearly fills the screen.
    private func addAreaHeight(viewport: CGFloat) -> CGFloat {
        let estimatedRows = CGFloat(orderedTasks.count) * 56
        return max(120, viewport - estimatedRows)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(Color.brand)
            Text("Nothing yet.")
                .foregroundStyle(Color.textSecondary)
            Text("Tap anywhere to add the first thing")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing { dismissEditing() } else { addTask() }
        }
    }

    /// Insert a fresh, empty task and drop the cursor straight into it.
    private func addTask() {
        // If a blank draft already exists, stay on it instead of stacking another.
        if let draft = tasks.first(where: {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            focusedTask = draft.id
            return
        }
        // New tasks land at the bottom of the open group. Insertion + ordering are
        // shared with the Siri/Shortcuts add intent via TaskActions.
        let item = withAnimation(.appMotion) { TaskActions.add(title: "", in: context) }
        Haptics.impact(.light)
        // Defer focus until the new row has been laid out.
        DispatchQueue.main.async {
            focusedTask = item.id
        }
    }

    /// Tapping off the field hides the keyboard; the row's commit-on-blur then
    /// discards the draft if it was left empty.
    private func dismissEditing() {
        if titleFocused { finishEditingTitle() }
        focusedTask = nil
    }

    /// Remove all completed tasks immediately (low-risk; only done items), then offer undo.
    private func clearCompleted() {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.clearCompleted(in: context) }
        Haptics.notify(.warning)
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        registerUndo(removed)
    }

    /// Remove every task (confirmed via dialog before this runs), then offer undo.
    private func clearAll() {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.clearAll(in: context) }
        Haptics.notify(.warning)
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        registerUndo(removed)
    }

    /// Add a just-removed batch to the rolling undo window. Accumulates across deletes
    /// and clears, and restarts the ~5s auto-dismiss timer (via a fresh `id`). No-op if
    /// nothing was removed.
    private func registerUndo(_ snapshots: [TaskSnapshot]) {
        guard !snapshots.isEmpty else { return }
        let combined = (pendingUndo?.snapshots ?? []) + snapshots
        pendingUndo = PendingUndo(snapshots: combined)
    }

    /// Dismiss the undo window without restoring (swipe-to-dismiss).
    private func dismissUndo() {
        withAnimation(.appMotion) { pendingUndo = nil }
    }

    /// Restore everything in the current undo window and dismiss the toast.
    private func undo() {
        guard let pending = pendingUndo else { return }
        withAnimation(.appMotion) { TaskActions.restore(pending.snapshots, in: context) }
        Haptics.selection()
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        pendingUndo = nil
    }

    /// Drag-to-reorder within the open group: renumber the open tasks to their new
    /// order and persist. Completed tasks are locked (clamped out by the helper).
    private func move(from source: IndexSet, to destination: Int) {
        let reordered = TaskOrdering.openOrderAfterMove(orderedTasks, from: source, to: destination)
        withAnimation(.appMotion) {
            for (index, task) in reordered.enumerated() {
                task.sortOrder = index
            }
        }
        try? context.save()
        Haptics.impact(.light)
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedTasks
        let toDelete = offsets.map { items[$0] }
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.delete(toDelete, in: context) }
        Haptics.notify(.warning)
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
        registerUndo(removed)
    }
}

/// The classic "we're live" indicator: a red dot that gently pulses while active.
private struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .opacity(pulse ? 1.0 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
