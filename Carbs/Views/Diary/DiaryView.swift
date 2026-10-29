import SwiftUI
import SwiftData

enum DiarySheet: Identifiable {
    case add(meal: Int)
    case quickAdd(meal: Int)
    case edit(FoodEntry)

    var id: String {
        switch self {
        case .add(let m): "add\(m)"
        case .quickAdd(let m): "quick\(m)"
        case .edit(let e): "edit\(e.id)"
        }
    }
}

struct DiaryView: View {
    @Bindable var profile: Profile
    @State private var date = Date.now.startOfDay

    var body: some View {
        NavigationStack {
            DayDiary(profile: profile, date: date)
                .screenBackground()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 18) {
                            Button { date = date.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                            Text(title).font(.headline).frame(minWidth: 150)
                            Button { date = date.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                        }
                    }
                    if date != Date.now.startOfDay {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Today") { date = Date.now.startOfDay }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        let calendar = Calendar.current
        let formatted = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if calendar.isDateInToday(date) { return "Today, \(date.formatted(.dateTime.month(.abbreviated).day()))" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(date.formatted(.dateTime.month(.abbreviated).day()))" }
        return formatted
    }
}

/// One day's summary and meals.
struct DayDiary: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: Profile
    let date: Date
    @Query private var entries: [FoodEntry]
    @State private var sheet: DiarySheet?
    @State private var showRemaining = false

    init(profile: Profile, date: Date) {
        self.profile = profile
        self.date = date
        let start = date.startOfDay, end = date.startOfDay.adding(days: 1)
        _entries = Query(filter: #Predicate<FoodEntry> { $0.timestamp >= start && $0.timestamp < end },
                         sort: \FoodEntry.timestamp)
    }

    var body: some View {
        let totals = DayTotals(entries)
        List {
            Section {
                SummaryCard(totals: totals, profile: profile, showRemaining: $showRemaining)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(profile.mealNames.enumerated()), id: \.offset) { index, name in
                mealSection(index: index, name: name)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let meal):
                AddFoodView(profile: profile, meal: meal, date: date, dayEntries: entries)
            case .quickAdd(let meal):
                QuickAddView(profile: profile, meal: meal, date: date)
            case .edit(let entry):
                EntryEditView(entry: entry, profile: profile)
            }
        }
    }

    @ViewBuilder
    private func mealSection(index: Int, name: String) -> some View {
        let items = entries.filter { $0.meal == index }
        let t = DayTotals(items)
        Section {
            ForEach(items) { entry in
                Button { sheet = .edit(entry) } label: { EntryRow(entry: entry) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for i in offsets { context.delete(items[i]) }
            }
            if Calendar.current.isDateInToday(date) {
                MealSuggestionRows(meal: index, date: date, logged: items)
            }
            if items.count > 1, t.carbs > 0 {
                let minutes = Absorption.suggestedMinutes(carbs: t.carbs, protein: t.protein, fat: t.fat)
                Label("Meal: \(t.carbs.rounded0) g carbs · \(Absorption.kind(minutes).lowercased()) absorption (\(Absorption.label(minutes)))",
                      systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(Theme.text)
                    Text("\(t.calories.rounded0) Cal, \(t.protein.rounded0)p, \(t.carbs.rounded0)c, \(t.fat.rounded0)f")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Menu {
                    Button { sheet = .quickAdd(meal: index) } label: { Label("Quick add", systemImage: "bolt") }
                    if !items.isEmpty && !Calendar.current.isDateInToday(date) {
                        Button { copyToToday(items) } label: { Label("Copy to today", systemImage: "doc.on.doc") }
                    }
                } label: {
                    Image(systemName: "ellipsis").padding(8)
                }
                Button { sheet = .add(meal: index) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.primary)
                }
            }
            .textCase(nil)
        }
    }

    private func copyToToday(_ items: [FoodEntry]) {
        let calendar = Calendar.current
        let today = Date.now.startOfDay
        for e in items {
            let time = calendar.dateComponents([.hour, .minute], from: e.timestamp)
            let stamp = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: today) ?? .now
            let copy = FoodEntry(timestamp: stamp, meal: e.meal, name: e.name, brand: e.brand, quantity: e.quantity,
                                 servingName: e.servingName, grams: e.grams, calories: e.calories, protein: e.protein,
                                 carbs: e.carbs, fat: e.fat, fiber: e.fiber, food: e.food, isQuickAdd: e.isQuickAdd)
            copy.absorptionMinutes = e.absorptionMinutes
            copy.absorptionIsManual = e.absorptionIsManual
            context.insert(copy)
        }
    }
}

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name + (entry.brand.map { " (\($0))" } ?? ""))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if entry.carbs >= 1 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    Text(Absorption.label(entry.absorptionMinutes))
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        let amount = entry.isQuickAdd ? "Quick add" : "\(entry.quantity.clean) \(entry.servingName)"
        return "\(amount) · \(entry.calories.rounded0) Cal, \(entry.protein.rounded1)p, \(entry.carbs.rounded1)c, \(entry.fat.rounded1)f"
    }
}

/// Concentric rings with eaten vs target, or what's left.
struct SummaryCard: View {
    let totals: DayTotals
    let profile: Profile
    @Binding var showRemaining: Bool

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $showRemaining) {
                Text("Consumed").tag(false)
                Text("Remaining").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 20) {
                ZStack {
                    ring(totals.calories, Double(profile.calories), Theme.primary, 96)
                    ring(totals.protein, Double(profile.protein), Theme.protein.opacity(0.7), 76)
                    ring(totals.carbs, Double(profile.carbs), Theme.carbs, 56)
                    ring(totals.fat, Double(profile.fat), Theme.fat, 36)
                }
                .frame(width: 100, height: 100)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Cal", nil, totals.calories, profile.calories)
                    row("Protein", Theme.protein, totals.protein, profile.protein)
                    row("Carbs", Theme.carbs, totals.carbs, profile.carbs)
                    row("Fat", Theme.fat, totals.fat, profile.fat)
                }
                .font(.subheadline)
            }
        }
        .card()
    }

    private func ring(_ value: Double, _ target: Double, _ color: Color, _ size: CGFloat) -> some View {
        let fraction = target > 0 ? value / target : 0
        return ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(1, fraction))
                .stroke(fraction > 1.03 ? Theme.error : color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func row(_ name: String, _ color: Color?, _ value: Double, _ target: Int) -> some View {
        let shown = showRemaining ? Double(target) - value : value
        return GridRow {
            HStack(spacing: 5) {
                if let color { Capsule().fill(color).frame(width: 4, height: 10) }
                Text(name)
            }
            Text(shown.rounded0)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(showRemaining && shown < 0 ? Theme.error : Theme.text)
                .gridColumnAlignment(.trailing)
            Text("\(target)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                .gridColumnAlignment(.trailing)
        }
    }
}
