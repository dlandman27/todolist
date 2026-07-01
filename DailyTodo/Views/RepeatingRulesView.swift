import SwiftUI
import SwiftData

/// The Settings screen listing your repeat rules. Each rule quietly adds an ordinary
/// task to Today on its schedule; here you create, edit, or delete the rules themselves.
struct RepeatingRulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RepeatRule.createdAt, order: .forward) private var rules: [RepeatRule]

    @State private var editingRule: RepeatRule?
    @State private var newRule: RepeatRule?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Form {
                Section {
                    ForEach(rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name.isEmpty ? "Untitled" : rule.name)
                                    .foregroundStyle(Color.textPrimary)
                                Text(rule.cadence?.summary() ?? "No schedule")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .listRowBackground(Color.appSurface)
                    }
                    .onDelete(perform: deleteRules)

                    Button(action: addRule) {
                        Label("Add repeating task", systemImage: "plus")
                            .foregroundStyle(Color.brand)
                    }
                    .listRowBackground(Color.appSurface)
                } footer: {
                    Text("Repeating tasks quietly add an ordinary to-do to your list on a schedule. Editing or deleting a repeat only affects future ones — tasks already added stay put.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Repeating")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRule) { rule in
            RepeatRuleEditorView(rule: rule, isNew: false)
        }
        .sheet(item: $newRule) { rule in
            RepeatRuleEditorView(rule: rule, isNew: true)
        }
    }

    private func addRule() {
        let rule = RepeatRule()
        context.insert(rule)
        newRule = rule
    }

    private func deleteRules(_ offsets: IndexSet) {
        for index in offsets { context.delete(rules[index]) }
        try? context.save()
    }
}
