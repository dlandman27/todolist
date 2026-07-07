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
    @State private var stashTarget: TaskItem?
    @State private var showStash = false
    @State private var showSettings = false
    @State private var showCustomize = false
    /// Where the fixed bar ends and where the big title currently sits, both in
    /// global coordinates — reported by geometry preferences. The title starts
    /// far offscreen-low so the inline title never flashes at launch.
    @State private var barBottom: CGFloat = 0
    @State private var titleMid: CGFloat? = .greatestFiniteMagnitude
    /// Sort preference shared with the widget + Live Activity via the App Group.
    @AppStorage(TaskSort.defaultsKey, store: AppGroup.defaults) private var sortRaw = TaskSort.manual.rawValue
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

    @Query(sort: \TaskItem.createdAt, order: .forward) private var tasks: [TaskItem]

    private var sortMode: TaskSort { TaskSort(rawValue: sortRaw) ?? .manual }

    /// Bulk actions (Stash All / Clear Completed / Clear All) are parked, not
    /// deleted — everything they need is still wired up behind this flag.
    private let showBulkActions = false

    /// True once the big title has scrolled under the control bar — the inline
    /// bar title fades in to take over. `nil` means the List recycled the title
    /// row entirely (scrolled far away), which also counts as collapsed.
    private var titleScrolledAway: Bool {
        guard let titleMid else { return true }
        return titleMid < barBottom
    }

    /// Open tasks first (in the chosen sort), completed ones sunk to the bottom —
    /// excluding stashed tasks, which live in the stash drawer.
    private var orderedTasks: [TaskItem] {
        TaskOrdering.ordered(tasks.filter { !$0.isStashed }, by: sortMode)
    }

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
                    .onTapGesture {
                        if showCustomize { showCustomize = false } else { dismissEditing() }
                    }
                VStack(spacing: 0) {
                    titleHeader
                    if orderedTasks.isEmpty {
                        titleView
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 10)
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
            .onPreferenceChange(BarBottomPreference.self) { barBottom = $0 }
            .onPreferenceChange(TitleMidPreference.self) { titleMid = $0 }
            // Floating Add button, overlaid so it doesn't reserve layout space (which
            // would shrink the list). Hidden while editing — the keyboard's there and
            // Return already chains to the next task.
            .overlay(alignment: .bottomTrailing) {
                if !isEditing {
                    addButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.appMotion, value: isEditing)
            // The undo toast animates up just above the bottom row, so it never
            // sits under the Add circle.
            .overlay(alignment: .bottom) {
                if let pending = pendingUndo {
                    UndoToast(message: pending.message, onUndo: undo, onDismiss: dismissUndo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 88)
                        .animation(.appMotion, value: pendingUndo?.id)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Settings is reached from the ellipsis menu (menus can't hold
            // NavigationLinks), so the push is driven by this flag instead.
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
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
        // If the focused task ceases to exist (deleted by any path while its row
        // was mid-edit), clear the dangling focus — otherwise the UI is stuck in
        // editing mode with no keyboard and no editable row.
        .onChange(of: tasks.count) { _, _ in
            if let focused = focusedTask, !tasks.contains(where: { $0.id == focused }) {
                focusedTask = nil
            }
        }
        .onChange(of: sortRaw) { _, _ in
            live.refresh()
            Surfaces.reload()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingUndo = nil }
        }
        .sheet(isPresented: $showStash) {
            StashSheet()
                .environment(live)
        }
        // Customize rides in a short glass sheet so the list stays visible and
        // recolors live behind it — the app itself is the preview.
        .sheet(isPresented: $showCustomize) {
            CustomizeView()
                .environment(theme)
                .environment(live)
                .presentationDetents([.height(380), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        // Reading theme.accent here makes ListView.body observe the accent, so the
        // whole tree repaints live on change; it also tints nav controls.
        .tint(theme.accent)
        // Fade, don't snap, when a new accent is picked in Customize.
        .animation(.easeInOut(duration: 0.35), value: theme.accentHex)
    }

    /// Reports the control bar's bottom edge in global coordinates.
    private struct BarBottomPreference: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    /// Reports the big title's vertical midpoint in global coordinates; nil when
    /// the List has recycled the title row offscreen.
    private struct TitleMidPreference: PreferenceKey {
        static let defaultValue: CGFloat? = nil
        static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
            value = nextValue() ?? value
        }
    }

    /// The fixed glass control bar — stash in its own capsule on the left, sort +
    /// list options sharing a capsule on the right. The title itself lives in the
    /// scroll content (`titleView`) so it slides away with the todos; once it
    /// passes under this bar, a compact copy fades into the bar's center.
    private var titleHeader: some View {
        HStack {
            stashButton
                .glassCapsule(tinted: false)
            Spacer()
            HStack(spacing: 2) {
                sortButton
                listOptionsButton
            }
            .glassCapsule(tinted: false)
            if isEditing {
                doneEditingButton
                    .glassCapsule(tinted: false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            // Compact stand-in for the scrolled-away big title. Decorative only —
            // the real (focusable, renamable) title is the one in the list.
            Text(listName)
                .font(.headline.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.brand)
                .lineLimit(1)
                .frame(maxWidth: 160)
                .opacity(titleScrolledAway ? 1 : 0)
                .offset(y: titleScrolledAway ? 0 : 8)
                .animation(.appMotion, value: titleScrolledAway)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BarBottomPreference.self,
                    value: proxy.frame(in: .global).maxY
                )
            }
        }
    }

    /// The list's title — double-tap to rename. Rendered inside the scrollable
    /// content (first list row / above the empty state), not the fixed bar.
    private var titleView: some View {
        titleContent
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TitleMidPreference.self,
                        value: proxy.frame(in: .global).midY
                    )
                }
            }
    }

    @ViewBuilder
    private var titleContent: some View {
        if editingTitle {
                TextField(ListSettings.defaultName, text: $listName)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.brand)
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
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.brand)
                    .accessibilityIdentifier("title")
                    .onTapGesture(count: 2, perform: beginEditingTitle)
        }
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
            // Bulk actions are hidden for now (not removed) while the menu slims
            // down to Customize + Settings — flip this to true to bring them back.
            if showBulkActions {
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
            }

            Section {
                Button {
                    showCustomize = true
                } label: {
                    Label("Customize", systemImage: "paintbrush")
                }
                .accessibilityIdentifier("customize")

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, height: 44)
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
            // Bag + inline count sharing the pill: the outline bag alone when the
            // stash is empty, "bag N" once items are in — the capsule stretching to
            // fit the number is itself the something-is-stashed signal.
            HStack(spacing: 0) {
                Image(systemName: stashedCount > 0 ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 24))
                    // Bounce the bag each time something lands in (or leaves) the stash.
                    .symbolEffect(.bounce, value: stashedCount)
                    .frame(width: 44, height: 44)
                if stashedCount > 0 {
                    Text("\(stashedCount)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .padding(.trailing, 14)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(Color.textPrimary)
            .animation(.appMotion, value: stashedCount)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("stash")
        .accessibilityLabel("Stashed todos, \(stashedCount) items")
    }

    /// Shown only while a task (or the title) is being edited: commits the edit
    /// and drops the keyboard. Accent-filled so it reads as the bar's one action.
    private var doneEditingButton: some View {
        Button {
            Haptics.impact(.light)
            dismissEditing()
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.brand)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("doneEditing")
        .accessibilityLabel("Done editing")
    }

    /// Sort menu — a non-destructive view preference. Manual is the drag order;
    /// the widget and Live Activity read the same stored mode, so every surface
    /// shows the list the same way.
    private var sortButton: some View {
        Menu {
            Picker("Sort By", selection: $sortRaw) {
                ForEach(TaskSort.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.impact(.light) })
        .accessibilityIdentifier("sortMenu")
        .accessibilityLabel("Sort")
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

    private var list: some View {
        // GeometryReader so the tap-to-add area can fill the full viewport height —
        // a fixed height leaves dead, non-tappable List background below it on tall screens.
        GeometryReader { geo in
            List {
                titleView
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))

                ForEach(orderedTasks) { task in
                    TaskRow(task: task, focus: $focusedTask, onReturn: addTask)
                        .listRowSeparator(.hidden)
                        // Override List's chunky default row insets. Leading 4 + the row's
                        // own 12pt content padding = 16, lining the checkbox up with the
                        // "Todo" title; tight top/bottom keeps rows close together.
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        // Completed rows are locked below the open group; the blank
                        // draft can't be dragged mid-edit.
                        .moveDisabled(task.done || task.isBlank || sortMode != .manual)
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
                    // With the Customize sheet up (background interaction on), a body
                    // tap should close the sheet — never add a todo underneath it.
                    if showCustomize {
                        showCustomize = false
                    } else if isEditing {
                        dismissEditing()
                    } else {
                        addTask()
                    }
                } label: {
                    Color.clear
                        .frame(minHeight: addAreaHeight(viewport: geo.size.height))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Transparent so the ThemeBackground shows through (it draws appBackground
            // itself when the kind is None, so the default look is unchanged).
            .background(Color.clear)
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
            if showCustomize {
                showCustomize = false
            } else if isEditing {
                dismissEditing()
            } else {
                addTask()
            }
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

