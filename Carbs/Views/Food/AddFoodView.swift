import SwiftUI
import SwiftData

enum FoodSource: Hashable {
    case saved(Food)
    case result(FoodResult)
}

/// Default time for a new entry: now for today, otherwise a typical time for the meal.
func defaultTimestamp(meal: Int, date: Date) -> Date {
    if Calendar.current.isDateInToday(date) { return .now }
    let hours = [8, 12, 18, 15, 10, 20, 21]
    return Calendar.current.date(bySettingHour: hours[min(meal, hours.count - 1)], minute: 0, second: 0, of: date) ?? date
}

struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var profile: Profile
    let meal: Int
    let date: Date
    let dayEntries: [FoodEntry]

    @Query(sort: \Food.lastUsed, order: .reverse) private var foods: [Food]
    @State private var query = ""
    @State private var results: [FoodResult] = []
    @State private var searching = false
    @State private var tab = 0
    @State private var path: [FoodSource] = []
    @State private var scanning = false
    @State private var creating = false
    @State private var scanMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RemainingHeader(profile: profile, totals: DayTotals(dayEntries))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                if query.isEmpty {
                    Picker("", selection: $tab) {
                        Text("Recent").tag(0)
                        Text("My Foods").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                List {
                    if let scanMessage {
                        Text(scanMessage).foregroundStyle(Theme.secondaryText)
                    }
                    if query.isEmpty {
                        ForEach(tab == 0 ? recent : myFoods) { food in
                            NavigationLink(value: FoodSource.saved(food)) { SavedFoodRow(food: food) }
                        }
                        if (tab == 0 ? recent : myFoods).isEmpty {
                            Text(tab == 0 ? "Foods you log show up here." : "Favorites and foods you create show up here.")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        let local = localMatches
                        if !local.isEmpty {
                            Section("My foods") {
                                ForEach(local) { food in
                                    NavigationLink(value: FoodSource.saved(food)) { SavedFoodRow(food: food) }
                                }
                            }
                        }
                        Section {
                            if searching && results.isEmpty {
                                HStack { ProgressView(); Text("Searching…").foregroundStyle(Theme.secondaryText) }
                            }
                            ForEach(results) { r in
                                NavigationLink(value: source(for: r)) { ResultRow(result: r) }
                            }
                            if !searching && results.isEmpty {
                                Text("No matches. Try fewer words, scan the barcode, or create the food.")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        } header: {
                            Text("USDA and Open Food Facts")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .screenBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .task(id: query) { await runSearch() }
            .navigationTitle(profile.mealNames[safe: meal] ?? "Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "square.and.pencil") }
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                }
            }
            .navigationDestination(for: FoodSource.self) { source in
                FoodDetailView(profile: profile, source: source, meal: meal, date: date, dayEntries: dayEntries) {
                    dismiss()
                }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScannerView { code in
                    scanning = false
                    Task { await handleBarcode(code) }
                }
            }
            .sheet(isPresented: $creating) {
                CreateFoodView { food in
                    creating = false
                    path.append(.saved(food))
                }
            }
        }
    }

    private var recent: [Food] { Array(foods.filter { $0.lastUsed != nil }.prefix(50)) }
    private var myFoods: [Food] { foods.filter { $0.isFavorite || $0.source == "custom" } }

    private var localMatches: [Food] {
        let words = query.lowercased().split(separator: " ")
        return foods.filter { food in
            let haystack = (food.name + " " + (food.brand ?? "")).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        .prefix(10).map { $0 }
    }

    /// Reuses a saved food when the same database item was logged before.
    private func source(for result: FoodResult) -> FoodSource {
        if let saved = foods.first(where: { $0.source == result.source && $0.sourceID == result.sourceID }) {
            return .saved(saved)
        }
        return .result(result)
    }

    private func runSearch() async {
        let q = query
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        searching = true
        let found = await FoodSearchService(usdaKey: profile.usdaAPIKey).search(q)
        guard !Task.isCancelled else { return }
        results = found
        searching = false
    }

    private func handleBarcode(_ code: String) async {
        if let saved = foods.first(where: { $0.barcode == code }) {
            path.append(.saved(saved))
            return
        }
        scanMessage = "Looking up \(code)…"
        if let found = await FoodSearchService(usdaKey: profile.usdaAPIKey).lookup(barcode: code) {
            scanMessage = nil
            path.append(.result(found))
        } else {
            scanMessage = "No food found for barcode \(code). You can create it with the pencil button."
        }
    }
}

struct RemainingHeader: View {
    let profile: Profile
    let totals: DayTotals
    var extra: (Double, Double, Double, Double) = (0, 0, 0, 0)

    var body: some View {
        HStack(spacing: 14) {
            item("\((Double(profile.calories) - totals.calories - extra.0).rounded0)", "Cal left", totals.calories + extra.0, profile.calories, Theme.primary)
            item("\((Double(profile.protein) - totals.protein - extra.1).rounded0)p", nil, totals.protein + extra.1, profile.protein, Theme.protein)
            item("\((Double(profile.carbs) - totals.carbs - extra.2).rounded0)c", nil, totals.carbs + extra.2, profile.carbs, Theme.carbs)
            item("\((Double(profile.fat) - totals.fat - extra.3).rounded0)f", nil, totals.fat + extra.3, profile.fat, Theme.fat)
        }
    }

    private func item(_ value: String, _ label: String?, _ used: Double, _ target: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                if let label { Text(label).font(.caption2).foregroundStyle(Theme.secondaryText) }
            }
            MacroBar(value: used, target: Double(target), color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SavedFoodRow: View {
    let food: Food
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if food.isFavorite { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.primary) }
                Text(food.name + (food.brand.map { " (\($0))" } ?? "")).lineLimit(2)
            }
            Text(summary).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var summary: String {
        if let last = food.recentAmounts.first {
            let parts = last.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let q = Double(parts[0]),
               let serving = food.allServings.first(where: { $0.name == parts[1] }) {
                let g = q * serving.grams
                return "\(parts[0]) \(parts[1]) · \((food.caloriesPer100g * g / 100).rounded0) Cal, \((food.proteinPer100g * g / 100).rounded1)p, \((food.carbsPer100g * g / 100).rounded1)c, \((food.fatPer100g * g / 100).rounded1)f"
            }
        }
        return "100 g · \(food.caloriesPer100g.rounded0) Cal, \(food.proteinPer100g.rounded1)p, \(food.carbsPer100g.rounded1)c, \(food.fatPer100g.rounded1)f"
    }
}

struct ResultRow: View {
    let result: FoodResult
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.name + (result.brand.map { " (\($0))" } ?? "")).lineLimit(2)
            Text(summary).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var summary: String {
        let s = result.servings.first
        let g = s?.grams ?? 100
        let label = s.map { $0.name } ?? "100 g"
        return "\(label) · \((result.caloriesPer100g * g / 100).rounded0) Cal, \((result.proteinPer100g * g / 100).rounded1)p, \((result.carbsPer100g * g / 100).rounded1)c, \((result.fatPer100g * g / 100).rounded1)f · \(result.sourceLabel)"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
