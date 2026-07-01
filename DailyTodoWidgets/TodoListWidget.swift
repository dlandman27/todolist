import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Timeline

struct WidgetTaskEntry: Identifiable {
    let id: UUID
    let title: String
    let done: Bool
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskEntry]
    /// Downsampled app background photo, only when the user opted the widget in.
    var backgroundImage: UIImage? = nil
    var openCount: Int { tasks.filter { !$0.done }.count }
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), tasks: [
            WidgetTaskEntry(id: UUID(), title: "Plan the day", done: false),
            WidgetTaskEntry(id: UUID(), title: "Morning coffee", done: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        // The app reloads timelines on every change, so a single entry is enough.
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> TodoEntry {
        let context = ModelContext(TaskStore.shared)
        let tasks = context.orderedTasks().map {
            WidgetTaskEntry(id: $0.id, title: $0.title, done: $0.done)
        }
        var backgroundImage: UIImage?
        if ThemeStore.showBackgroundOnWidget, ThemeStore.backgroundKind == .photo {
            backgroundImage = ThemeStore.loadBackgroundImage(maxDimension: 900)
        }
        return TodoEntry(date: Date(), tasks: tasks, backgroundImage: backgroundImage)
    }
}

// MARK: - View

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.openCount) to do")
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            systemView
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemLarge: return 9
        case .systemSmall: return 3
        default: return 4
        }
    }

    private var systemView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(ListSettings.name)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Link(destination: DeepLink.addURL) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                }
            }
            if entry.tasks.isEmpty {
                Spacer()
                Text("Nothing yet")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(maxRows)) { row($0) }
                if entry.tasks.count > maxRows {
                    Text("+\(entry.tasks.count - maxRows) more")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    /// The home-screen widget background: mirrors the app background when the user
    /// opted in, otherwise the flat app color.
    @ViewBuilder
    private var widgetBackground: some View {
        if ThemeStore.showBackgroundOnWidget {
            ThemeBackgroundContent(
                kind: ThemeStore.backgroundKind,
                colorHex: ThemeStore.backgroundColorHex,
                gradientTop: ThemeStore.gradientTopHex,
                gradientBottom: ThemeStore.gradientBottomHex,
                image: entry.backgroundImage
            )
        } else {
            Color.appBackground
        }
    }

    private func row(_ task: WidgetTaskEntry) -> some View {
        Button(intent: ToggleTaskIntent(taskID: task.id)) {
            HStack(spacing: 8) {
                Image(systemName: TaskStyle.checkboxSymbol(done: task.done))
                    .foregroundStyle(task.done ? Color.brand : Color.textSecondary)
                TaskStyle.title(task.title, done: task.done, primary: .textPrimary, muted: .textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ListSettings.name).font(.caption2).bold()
            if entry.tasks.isEmpty {
                Text("Nothing yet").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(entry.tasks.prefix(3)) { task in
                    HStack(spacing: 4) {
                        Image(systemName: task.done ? "checkmark.circle" : "circle")
                            .font(.system(size: 9))
                        Text(task.title)
                            .font(.caption2)
                            .strikethrough(task.done)
                            .lineLimit(1)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetAccentable()
    }

    private var accessoryCircular: some View {
        VStack(spacing: 0) {
            Image(systemName: "checklist").font(.caption2)
            Text("\(entry.openCount)").font(.headline)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Configuration

struct TodoListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoListWidget", provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("To-Do")
        .description("Your list — check things off without opening the app.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}
