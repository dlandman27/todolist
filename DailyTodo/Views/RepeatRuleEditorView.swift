import SwiftUI
import SwiftData

/// Edits a single repeat rule: its name and its weekly/monthly schedule. Local pickers
/// build a `RepeatCadence`, committed to the rule on Save. Delete removes the rule only
/// (already-spawned tasks are independent and untouched).
struct RepeatRuleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var rule: RepeatRule
    /// True when this rule was newly created for this sheet, so Cancel discards it.
    var isNew: Bool

    private enum Mode: String, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case monthly = "Monthly"
        var id: String { rawValue }
    }

    @State private var name: String = ""
    @State private var mode: Mode = .weekly
    @State private var weekdays: Set<Int> = [2]      // default Monday
    @State private var monthDays: Set<Int> = [1]     // default 1st

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Water plants", text: $name)
                }
                Section("Repeats") {
                    Picker("Frequency", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .weekly:  weekdayPicker
                    case .monthly: monthDayPicker
                    }
                }
                if !isNew {
                    Section {
                        Button(role: .destructive, action: deleteRule) {
                            Text("Delete repeat")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Repeat" : "Edit Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onAppear(perform: loadFromRule)
        }
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(1...7, id: \.self) { d in
                let on = weekdays.contains(d)
                Button {
                    if on { weekdays.remove(d) } else { weekdays.insert(d) }
                } label: {
                    Text(RepeatCadence.weekdayShortNames[d].prefix(1))
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Color.brand : Color.appSurface))
                        .foregroundStyle(on ? .white : Color.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthDayPicker: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...31, id: \.self) { d in
                let on = monthDays.contains(d)
                Button {
                    if on { monthDays.remove(d) } else { monthDays.insert(d) }
                } label: {
                    Text("\(d)")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.brand : Color.appSurface))
                        .foregroundStyle(on ? .white : Color.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isValid: Bool {
        let named = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch mode {
        case .weekly:  return named && !weekdays.isEmpty
        case .monthly: return named && !monthDays.isEmpty
        }
    }

    private func loadFromRule() {
        name = rule.name
        switch rule.cadence {
        case .weekly(let d):  mode = .weekly; weekdays = d
        case .monthly(let d): mode = .monthly; monthDays = d
        case .none: break
        }
    }

    private func save() {
        rule.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .weekly:  rule.cadence = .weekly(weekdays)
        case .monthly: rule.cadence = .monthly(monthDays)
        }
        try? context.save()
        Haptics.selection()
        dismiss()
    }

    /// Cancel: discard a brand-new rule so an abandoned "add" leaves nothing behind.
    private func cancel() {
        if isNew { context.delete(rule); try? context.save() }
        dismiss()
    }

    private func deleteRule() {
        context.delete(rule)
        try? context.save()
        Haptics.impact(.light)
        dismiss()
    }
}
