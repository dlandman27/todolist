import SwiftUI

/// One place for how a task is presented across every surface — app, widget, and
/// Live Activity — so completed-task styling can't drift between them.
enum TaskStyle {
    /// The checkbox SF Symbol for a given done state.
    static func checkboxSymbol(done: Bool) -> String {
        done ? "checkmark.circle.fill" : "circle"
    }

    /// A task title styled for its done state: muted and struck through when complete.
    ///
    /// The foreground color is applied *before* the strikethrough so the line inherits
    /// the (rendering) text color — passing an explicit dynamic color to `strikethrough`
    /// fails to render in archived widgets, which is why the line was invisible there.
    static func title(_ title: String, done: Bool, primary: Color, muted: Color) -> Text {
        Text(title)
            .foregroundStyle(done ? muted : primary)
            .strikethrough(done)
    }
}
