import WidgetKit
import SwiftUI

@main
struct DailyTodoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoListWidget()
        TodoLiveActivity()
    }
}
