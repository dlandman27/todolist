import SwiftUI
import SwiftData
import WidgetKit

/// The whole app: one running list you add to inline, check off, edit, and delete.
struct ListView: View {
    @Environment(Router.self) private var router
    @Environment(LiveActivityController.self) private var live
    @Environment(\.modelContext) private var context
    @FocusState private var focusedTask: UUID?

    @Query(sort: \TaskItem.createdAt, order: .forward) private var tasks: [TaskItem]

    /// Open tasks first (creation order), completed ones sunk to the bottom
    /// in the order they were checked off.
    private var orderedTasks: [TaskItem] {
        let open = tasks.filter { !$0.done }
        let done = tasks.filter { $0.done }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        return open + done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleHeader
                    if tasks.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { liveActivityButton }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: router.addRequested) { _, requested in
            if requested {
                addTask()
                router.addRequested = false
            }
        }
    }

    /// The app's only title.
    private var titleHeader: some View {
        Text("To-Do")
            .font(.largeTitle.bold())
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
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
                withAnimation(.snappy) { live.toggle() }
            } label: {
                if live.isRunning {
                    Label("Live on Lock Screen", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.brand)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(Color.brandTint))
                } else {
                    Label("Pin to Lock Screen", systemImage: "pin.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(Capsule().fill(Color.brand))
                        .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 4)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private var list: some View {
        List {
            ForEach(orderedTasks) { task in
                TaskRow(task: task, focus: $focusedTask, onReturn: addTask)
                    .listRowSeparator(.hidden)
            }
            .onDelete(perform: delete)

            // The empty space below the list is a tap target for adding a task.
            Color.clear
                .frame(minHeight: 400)
                .listRowBackground(Color.appBackground)
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
                .onTapGesture(perform: addTask)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
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
        .onTapGesture(perform: addTask)
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
        let item = TaskItem(title: "")
        context.insert(item)
        try? context.save()
        // Defer focus until the new row has been laid out.
        DispatchQueue.main.async {
            focusedTask = item.id
        }
    }

    private func delete(_ offsets: IndexSet) {
        let items = orderedTasks
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
        LiveActivityController.shared.refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
