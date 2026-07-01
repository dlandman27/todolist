import SwiftUI
import SwiftData
import WidgetKit
import UIKit

/// The whole app: one running list you add to inline, check off, edit, and delete.
struct ListView: View {
    @Environment(Router.self) private var router
    @Environment(LiveActivityController.self) private var live
    @Environment(\.modelContext) private var context
    @FocusState private var focusedTask: UUID?
    @AppStorage(ListSettings.nameKey, store: AppGroup.defaults) private var listName = ListSettings.defaultName
    // Observing the theme model repaints the whole list the moment the accent
    // changes (Color.brand then re-reads the now-updated ThemeStore).
    @Environment(ThemeModel.self) private var theme
    @State private var editingTitle = false
    @FocusState private var titleFocused: Bool
    @State private var showClearAllConfirm = false
    @State private var showClearCompletedConfirm = false
    @State private var pendingUndo: PendingUndo?
    /// A brief auto-dismissing status message shown when toggling the Live Activity.
    @State private var liveToast: LiveToast?
    @State private var stashTarget: TaskItem?
    @State private var showStash = false
    @State private var showStashAllPicker = false
    /// Tasks mid-stash — their row exits by shrinking toward the bag instead of a plain fade.
    @State private var stashingIDs: Set<UUID> = []
    @Environment(\.scenePhase) private var scenePhase

    /// Tasks removed within the current undo window, accumulated across deletes and
    /// clears, held in memory only while the toast is up. `id` changes on every new
    /// removal so the auto-dismiss timer restarts (a rolling 5s window).
    private struct PendingUndo {
        let id = UUID()
        let snapshots: [TaskSnapshot]
        var message: String { "Removed \(snapshots.count) task\(snapshots.count == 1 ? "" : "s")" }
    }

    /// A transient Live Activity status message. `id` changes each time so the
    /// auto-dismiss timer restarts on a fresh toggle.
    private struct LiveToast {
        let id = UUID()
        let message: String
    }

    @Query(sort: \TaskItem.createdAt, order: .forward) private var tasks: [TaskItem]

    /// Open tasks first, completed ones sunk to the bottom — excluding stashed tasks,
    /// which live in the stash drawer.
    private var orderedTasks: [TaskItem] { TaskOrdering.ordered(tasks.filter { !$0.isStashed }) }

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

    /// Tasks the user can actually see — excludes the in-progress blank draft row so
    /// the "Delete all" dialog never claims a count the empty-looking list contradicts.
    private var visibleTaskCount: Int { tasks.filter { !$0.isBlank && !$0.isStashed }.count }

    /// Number of stashed tasks — drives the header bag's fill state and count badge.
    /// Blank stashed drafts (being typed in the stash sheet) don't count yet.
    private var stashedCount: Int { tasks.filter { $0.isStashed && !$0.isBlank }.count }

    /// Open, real (non-blank) tasks in Today — what "Stash All Todos" would stash.
    private var stashableTasks: [TaskItem] { orderedTasks.filter { !$0.done && !$0.isBlank } }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()
                    .contentShape(Rectangle())
                    // Tapping empty chrome (header, sides) only dismisses an active edit —
                    // it must NOT add a task. Adding is handled by the explicit areas below.
                    .onTapGesture { dismissEditing() }
                VStack(spacing: 0) {
                    titleHeader
                    if orderedTasks.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        list
                            .transition(.opacity)
                    }
                }
                // Cross-fade between the list and the empty state on any path to/from
                // empty (clear, last row deleted, discarded draft).
                .animation(.appMotion, value: orderedTasks.isEmpty)
            }
            // Floating Add button, overlaid so it doesn't reserve layout space (which
            // would shrink the list). Hidden while editing — the keyboard's there and
            // Return already chains to the next task.
            // Bottom controls float as a symmetric pair — Go Live bottom-left, Add
            // bottom-right — both hidden while editing so they don't crowd the keyboard.
            .overlay(alignment: .bottomLeading) {
                if !isEditing {
                    liveActivityButton
                        .padding(.leading, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isEditing {
                    addButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.appMotion, value: isEditing)
            // Transient toasts (undo + Live Activity status) animate up just above the
            // bottom button row, so they never sit under the Add / Go Live circles.
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let pending = pendingUndo {
                        UndoToast(message: pending.message, onUndo: undo, onDismiss: dismissUndo)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let toast = liveToast {
                        InfoToast(message: toast.message) {
                            withAnimation(.appMotion) { liveToast = nil }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 88)
                .animation(.appMotion, value: pendingUndo?.id)
                .animation(.appMotion, value: liveToast?.id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Delete all \(visibleTaskCount) tasks?",
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
            .confirmationDialog(
                "Stash this task",
                isPresented: Binding(
                    get: { stashTarget != nil },
                    set: { if !$0 { stashTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(StashDuration.allCases) { option in
                    Button(option.label) { stash(stashTarget, for: option) }
                }
                Button("Cancel", role: .cancel) { stashTarget = nil }
            } message: {
                Text("Hide it from Today until later.")
            }
            .confirmationDialog(
                "Stash all todos",
                isPresented: $showStashAllPicker,
                titleVisibility: .visible
            ) {
                ForEach(StashDuration.allCases) { option in
                    Button(option.label) { stashAll(for: option) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Hide every open task from Today until later.")
            }
        }
        .onChange(of: router.addRequested) { _, requested in
            if requested {
                addTask()
                router.addRequested = false
            }
        }
        .onChange(of: router.stashRequested) { _, requested in
            if requested {
                showStash = true
                router.stashRequested = false
            }
        }
        .task(id: pendingUndo?.id) {
            guard pendingUndo != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.appMotion) { pendingUndo = nil }
        }
        .task(id: liveToast?.id) {
            guard liveToast != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.appMotion) { liveToast = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingUndo = nil }
        }
        .sheet(isPresented: $showStash) {
            StashSheet()
                .environment(live)
                .environment(theme)
        }
        // Reading theme.accent here makes ListView.body observe the accent, so the
        // whole tree repaints live on change; it also tints nav controls.
        .tint(theme.accent)
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
                stashButton
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
        Surfaces.reload()
    }

    /// The ⋯ list-options menu: bulk actions on this list. Sections keep room for a
    /// future "Sort By" section without adding another header button.
    private var listOptionsButton: some View {
        Menu {
            Button {
                showStashAllPicker = true
            } label: {
                Label("Stash All Todos", systemImage: "archivebox")
            }
            .disabled(stashableTasks.isEmpty)

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
                .disabled(orderedTasks.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.impact(.light) })
        .accessibilityIdentifier("listOptions")
        .accessibilityLabel("List options")
    }

    /// Header bag that opens the stash drawer. Outline when empty, filled + count when not.
    private var stashButton: some View {
        Button {
            Haptics.impact(.light)
            showStash = true
        } label: {
            Image(systemName: stashedCount > 0 ? "archivebox.fill" : "archivebox")
                .font(.title2)
                .foregroundStyle(Color.brand)
                // Bounce the bag each time something lands in (or leaves) the stash.
                .symbolEffect(.bounce, value: stashedCount)
                .frame(width: 30, height: 44)
                .overlay(alignment: .topTrailing) {
                    if stashedCount > 0 {
                        Text("\(stashedCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .padding(3)
                            .background(Circle().fill(Color.stashAccent))
                            // Tucked at the top-right, inside the glass capsule.
                            .offset(x: -1, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.appMotion, value: stashedCount)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("stash")
        .accessibilityLabel("Stashed todos, \(stashedCount) items")
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
        .simultaneousGesture(TapGesture().onEnded { Haptics.impact(.light) })
        .accessibilityIdentifier("settings")
        .accessibilityLabel("Settings")
    }

    /// The primary action: a solid, always-visible "+" that adds a task. Reuses
    /// `addTask()` so it inherits the focus-the-existing-draft behavior, and carries
    /// an accessibility label so VoiceOver users can add a task from the main screen
    /// (tapping empty space — the other add path — is invisible to VoiceOver).
    private var addButton: some View {
        Button(action: addTask) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.brand))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addTask")
        .accessibilityLabel("Add task")
    }

    /// Bottom-left control to pin the list to the Lock Screen as a Live Activity.
    /// An icon-only circle sized to mirror the Add button, but glass (quiet) so it
    /// reads as secondary to the solid Add FAB. Brand-colored and pulsing while live,
    /// muted otherwise. (A 56pt capsule is a circle — reuses `glassCapsule`.)
    @ViewBuilder
    private var liveActivityButton: some View {
        if live.systemEnabled {
            Button {
                Haptics.impact(.medium)
                withAnimation(.snappy) { live.toggle() }
                // Confirm the (otherwise silent) state change — the button itself is
                // text-free, so the toast is what tells the user what just happened.
                liveToast = LiveToast(message: live.isRunning
                    ? "You're now live. Tasks will show in your Live Activities."
                    : "Live Activities disabled.")
            } label: {
                // The slash carries the off/on meaning: a clear antenna (brand-red +
                // tinted glass) when live, a slashed muted antenna when not — so the
                // state reads at a glance, not just by color. No animation (visual noise).
                Image(systemName: live.isRunning
                    ? "antenna.radiowaves.left.and.right"
                    : "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(live.isRunning ? Color.brand : Color.textSecondary)
                    .frame(width: 56, height: 56)
                    .glassCapsule(tinted: live.isRunning)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(live.isRunning ? "Live on Lock Screen, tap to stop" : "Show list on Lock Screen")
        } else {
            // Live Activities are off system-wide — the tap sends the user to Settings.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 56, height: 56)
                    .glassCapsule(tinted: false)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live Activities are off. Open Settings")
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
                        // Swipe the opposite way from delete to stash — open tasks only.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !task.done && !task.isBlank {
                                Button {
                                    Haptics.impact(.light)
                                    stashTarget = task
                                } label: {
                                    Label("Stash", systemImage: "archivebox")
                                }
                                .tint(Color.stashAccent)
                            }
                        }
                        // Stashed rows shrink toward the top-right (the bag); everything
                        // else just fades.
                        .transition(
                            stashingIDs.contains(task.id)
                                ? .scale(scale: 0.15, anchor: .topTrailing).combined(with: .opacity)
                                : .opacity
                        )
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
        // If a blank Today draft already exists, stay on it instead of stacking another.
        // Exclude stashed drafts — those belong to the stash sheet, not Today.
        if let draft = tasks.first(where: {
            !$0.isStashed && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// Stash every open Today task for the chosen duration.
    private func stashAll(for option: StashDuration) {
        let toStash = stashableTasks
        guard !toStash.isEmpty else { return }
        let ids = Set(toStash.map(\.id))
        stashingIDs = ids
        let returnDate = option.returnDate()
        withAnimation(.appMotion) {
            for task in toStash { TaskActions.stash(task, until: returnDate, in: context) }
        }
        Haptics.selection()
        live.refresh()
        Surfaces.reload()
        clearStashing(ids)
    }

    /// Stash the targeted task for the chosen duration, then dismiss the picker.
    private func stash(_ task: TaskItem?, for option: StashDuration) {
        guard let task else { return }
        stashingIDs = [task.id]
        withAnimation(.appMotion) {
            TaskActions.stash(task, until: option.returnDate(), in: context)
        }
        Haptics.selection()
        live.refresh()
        Surfaces.reload()
        stashTarget = nil
        clearStashing([task.id])
    }

    /// Drop ids from `stashingIDs` once their fly-to-bag exit has played.
    private func clearStashing(_ ids: Set<UUID>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { stashingIDs.subtract(ids) }
    }

    /// Remove all completed tasks immediately (low-risk; only done items), then offer undo.
    private func clearCompleted() {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.clearCompleted(in: context) }
        Haptics.notify(.warning)
        live.refresh()
        Surfaces.reload()
        registerUndo(removed)
    }

    /// Remove every task (confirmed via dialog before this runs), then offer undo.
    private func clearAll() {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.clearAll(in: context) }
        Haptics.notify(.warning)
        live.refresh()
        Surfaces.reload()
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
        Surfaces.reload()
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
        Surfaces.reload()
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedTasks
        let toDelete = offsets.map { items[$0] }
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.delete(toDelete, in: context) }
        Haptics.notify(.warning)
        live.refresh()
        Surfaces.reload()
        registerUndo(removed)
    }
}

