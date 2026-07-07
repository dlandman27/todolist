import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// The lock-screen hero: the list as a Live Activity. Check items off right here
/// (App Intent), or tap + to jump into the app to add.
struct TodoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodoActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.appBackground)
                .activitySystemActionForegroundColor(Color.brand)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ListSettings.name, systemImage: "checklist")
                        .font(.caption).bold()
                        .foregroundStyle(Color.brand)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.openCount) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if context.state.tasks.isEmpty {
                            Text("Nothing yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            // Dynamic Island is always dark — use light text here.
                            ForEach(context.state.tasks.prefix(3)) {
                                LiveTaskRow(task: $0, primaryText: .white, mutedText: .white.opacity(0.6))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: "checklist").foregroundStyle(Color.brand)
            } compactTrailing: {
                Text("\(context.state.openCount)")
            } minimal: {
                Text("\(context.state.openCount)").foregroundStyle(Color.brand)
            }
        }
    }
}

private struct LockScreenLiveView: View {
    let state: TodoActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(ListSettings.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                Text("\(state.openCount) left")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Link(destination: DeepLink.addURL) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.brand)
                }
            }

            if state.tasks.isEmpty {
                Text("Nothing yet")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(state.tasks.prefix(3)) { LiveTaskRow(task: $0, font: .body) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        // The system killed the activity (8h limit) — dim so old checkmarks don't read as current.
        .opacity(isStale ? 0.55 : 1)
    }
}

private struct LiveTaskRow: View {
    let task: LiveTask
    var primaryText: Color = .textPrimary
    var mutedText: Color = .textSecondary
    var font: Font = .subheadline

    var body: some View {
        Button(intent: ToggleTaskIntent(taskID: task.id)) {
            HStack(spacing: 10) {
                Image(systemName: TaskStyle.checkboxSymbol(done: task.done))
                    .foregroundStyle(task.done ? Color.brand : mutedText)
                TaskStyle.title(task.title, done: task.done, primary: primaryText, muted: mutedText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(font)
        }
        .buttonStyle(.plain)
    }
}
