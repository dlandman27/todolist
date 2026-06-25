import SwiftUI
import SwiftData
import WidgetKit

/// The stash drawer, presented as a bottom sheet. Its own little world: stashed tasks
/// sorted soonest-return-first, with bring-back / complete / delete / re-snooze, plus a
/// self-contained rolling undo walled off from the Today list's undo.
struct StashSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(LiveActivityController.self) private var live
    @Environment(\.scenePhase) private var scenePhase

    @Query private var allTasks: [TaskItem]

    @State private var pendingUndo: PendingUndo?
    @State private var resnoozeTarget: TaskItem?

    /// Stash-only rolling undo (delete / Clear Stash), walled off from the Today undo.
    private struct PendingUndo {
        let id = UUID()
        let snapshots: [TaskSnapshot]
        var message: String { "Removed \(snapshots.count) task\(snapshots.count == 1 ? "" : "s")" }
    }

    private var stashed: [TaskItem] {
        allTasks.filter { $0.isStashed }
            .sorted { ($0.stashReturnDate ?? .distantFuture) < ($1.stashReturnDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                List {
                    ForEach(stashed) { task in
                        StashRow(task: task) { complete(task) }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { bringBack(task) } label: {
                                    Label("To Today", systemImage: "tray.and.arrow.up")
                                }
                                .tint(Color.stashAccent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { deleteFromStash(task) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { resnoozeTarget = task }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 36)
                .animation(.appMotion, value: stashed.map(\.id))

                if let pending = pendingUndo {
                    VStack {
                        Spacer()
                        UndoToast(message: pending.message, onUndo: undo, onDismiss: dismissUndo)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.appMotion, value: pendingUndo?.id)
                }
            }
            .navigationTitle("Stash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { clearStash() } label: {
                        Label("Clear Stash", systemImage: "trash")
                    }
                    .disabled(stashed.isEmpty)
                }
            }
            .confirmationDialog(
                "Re-stash this task",
                isPresented: Binding(
                    get: { resnoozeTarget != nil },
                    set: { if !$0 { resnoozeTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(StashDuration.allCases) { option in
                    Button(option.label) { resnooze(resnoozeTarget, for: option) }
                }
                Button("Cancel", role: .cancel) { resnoozeTarget = nil }
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Pull a task back into Today now.
    private func bringBack(_ task: TaskItem) {
        withAnimation(.appMotion) { TaskActions.unstash(task, in: context) }
        Haptics.selection()
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Complete a task straight from the stash: un-stash, then mark done.
    private func complete(_ task: TaskItem) {
        withAnimation(.appMotion) {
            TaskActions.unstash(task, in: context)
            _ = TaskActions.complete(id: task.id, in: context)
        }
        Haptics.notify(.success)
        live.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Delete one stashed task, registering the sheet-local undo.
    private func deleteFromStash(_ task: TaskItem) {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.delete([task], in: context) }
        Haptics.notify(.warning)
        WidgetCenter.shared.reloadAllTimelines()
        registerUndo(removed)
    }

    /// Empty the whole stash, registering the sheet-local undo.
    private func clearStash() {
        var removed: [TaskSnapshot] = []
        withAnimation(.appMotion) { removed = TaskActions.clearStash(in: context) }
        Haptics.notify(.warning)
        WidgetCenter.shared.reloadAllTimelines()
        registerUndo(removed)
    }

    /// Change a stashed task's return time.
    private func resnooze(_ task: TaskItem?, for option: StashDuration) {
        guard let task else { return }
        withAnimation(.appMotion) {
            TaskActions.stash(task, until: option.returnDate(), in: context)
        }
        Haptics.selection()
        WidgetCenter.shared.reloadAllTimelines()
        resnoozeTarget = nil
    }

    /// Accumulate removed snapshots into the sheet-local rolling undo window.
    private func registerUndo(_ snapshots: [TaskSnapshot]) {
        guard !snapshots.isEmpty else { return }
        pendingUndo = PendingUndo(snapshots: (pendingUndo?.snapshots ?? []) + snapshots)
    }

    /// Restore everything in the sheet's undo window back into the stash.
    private func undo() {
        guard let pending = pendingUndo else { return }
        withAnimation(.appMotion) { TaskActions.restore(pending.snapshots, in: context) }
        Haptics.selection()
        WidgetCenter.shared.reloadAllTimelines()
        pendingUndo = nil
    }

    /// Swipe-to-dismiss the undo toast without restoring.
    private func dismissUndo() {
        withAnimation(.appMotion) { pendingUndo = nil }
    }
}
