import SwiftUI
import SwiftData

/// "Suggested" rows under a meal: foods often eaten at this meal, added with one tap.
struct MealSuggestionRows: View {
    @Environment(\.modelContext) private var context
    let meal: Int
    let date: Date
    let logged: [FoodEntry]
    @Query private var history: [FoodEntry]
    @State private var expanded = true
    @State private var dismissed: Set<UUID> = []

    init(meal: Int, date: Date, logged: [FoodEntry]) {
        self.meal = meal
        self.date = date
        self.logged = logged
        let end = date.startOfDay, start = end.adding(days: -14)
        _dismissed = State(initialValue: Set((UserDefaults.standard.stringArray(forKey: Self.dismissKey(meal, date)) ?? [])
            .compactMap(UUID.init)))
        _history = Query(filter: #Predicate<FoodEntry> { $0.meal == meal && $0.timestamp >= start && $0.timestamp < end && !$0.isQuickAdd },
                         sort: \FoodEntry.timestamp)
    }

    /// Dismissals last for the rest of the day.
    private static func dismissKey(_ meal: Int, _ date: Date) -> String {
        "dismissedSuggestions.\(date.formatted(.iso8601.year().month().day())).\(meal)"
    }

    private var suggestions: [(food: Food, pick: MealSuggestions.Pick)] {
        var foods: [UUID: Food] = [:]
        let uses = history.compactMap { e -> MealSuggestions.Use? in
            guard let food = e.food else { return nil }
            foods[food.id] = food
            return .init(foodID: food.id, timestamp: e.timestamp, quantity: e.quantity, servingName: e.servingName)
        }
        let skip = Set(logged.compactMap { $0.food?.id }).union(dismissed)
        return MealSuggestions.suggest(history: uses, before: date, excluding: skip)
            .compactMap { pick in foods[pick.foodID].map { ($0, pick) } }
    }

    var body: some View {
        let list = suggestions
        if !list.isEmpty {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack {
                    Text(expanded ? "SUGGESTED" : "SUGGESTED (\(list.count))")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(list, id: \.pick.foodID) { item in
                    row(title: item.food.name + (item.food.brand.map { " (\($0))" } ?? ""),
                        detail: detail(item.food, item.pick),
                        dismiss: { dismiss([item.pick.foodID]) },
                        add: { add([item]) })
                }
                if list.count > 1 {
                    row(title: "All", detail: nil,
                        dismiss: { dismiss(list.map(\.pick.foodID)) },
                        add: { add(list) })
                }
            }
        }
    }

    private func row(title: String, detail: String?, dismiss: @escaping () -> Void, add: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(Theme.text).lineLimit(2)
                if let detail { Text(detail).font(.caption).foregroundStyle(Theme.secondaryText) }
            }
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.secondaryText.opacity(0.5))
            }
            .accessibilityLabel("Dismiss \(title)")
            Button(action: add) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.primary)
            }
            .accessibilityLabel("Add \(title)")
        }
        .buttonStyle(.borderless)
    }

    private func detail(_ food: Food, _ pick: MealSuggestions.Pick) -> String {
        let grams = pick.quantity * serving(food, pick).grams
        let n = { (per100: Double) in per100 * grams / 100 }
        return "\(pick.quantity.clean) \(pick.servingName) · \(n(food.caloriesPer100g).rounded0) Cal, "
            + "\(n(food.proteinPer100g).rounded1)p, \(n(food.carbsPer100g).rounded1)c, \(n(food.fatPer100g).rounded1)f"
    }

    private func serving(_ food: Food, _ pick: MealSuggestions.Pick) -> ServingOption {
        food.allServings.first { $0.name == pick.servingName } ?? food.allServings[0]
    }

    private func dismiss(_ ids: [UUID]) {
        withAnimation { dismissed.formUnion(ids) }
        UserDefaults.standard.set(dismissed.map(\.uuidString), forKey: Self.dismissKey(meal, date))
    }

    private func add(_ items: [(food: Food, pick: MealSuggestions.Pick)]) {
        for (food, pick) in items {
            let entry = FoodEntry(timestamp: defaultTimestamp(meal: meal, date: date), meal: meal, name: food.name, brand: food.brand,
                                  quantity: pick.quantity, servingName: pick.servingName, grams: 0,
                                  calories: 0, protein: 0, carbs: 0, fat: 0, food: food)
            entry.apply(quantity: pick.quantity, serving: serving(food, pick), from: food)
            // Keep an absorption time that was set by hand last time.
            if let last = history.last(where: { $0.food?.id == food.id }), last.absorptionIsManual {
                entry.absorptionMinutes = last.absorptionMinutes
                entry.absorptionIsManual = true
            }
            entry.loopStatus = entry.carbs >= 1 ? .pending : .none
            context.insert(entry)
            food.recordUse(quantity: pick.quantity, serving: pick.servingName)
        }
        try? context.save()
    }
}
