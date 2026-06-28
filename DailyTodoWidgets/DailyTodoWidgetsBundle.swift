import WidgetKit
import SwiftUI

@main
struct DailyTodoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoListWidget()
        TodoLiveActivity()
        if #available(iOS 18.0, *) {
            QuickAddControl()
            TasksLeftControl()
            StashedControl()
        }
    }
}
