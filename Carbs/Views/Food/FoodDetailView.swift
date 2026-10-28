import SwiftUI
import SwiftData

/// Pick an amount, time and absorption, then add to the diary.
struct FoodDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: Profile
    let source: FoodSource
    let meal: Int
    let date: Date
    let dayEntries: [FoodEntry]
    var onAdded: () -> Void

    @State private var quantity: Double = 1
    @State private var servingName = ""
    @State private var timestamp = Date.now
    @State private var absorption = 120
    @State private var absorptionManual = false
    @State private var favorite = false
    @State private var loaded = false

    private var name: String {
        switch source { case .saved(let f): f.name; case .result(let r): r.name }
    }
    private var brand: String? {
        switch source { case .saved(let f): f.brand; case .result(let r): r.brand }
    }
    private var servings: [ServingOption] {
        switch source {
        case .saved(let f): f.allServings
        case .result(let r): r.servings + [.gram, .ounce]
        }
    }
    private var per100: (Double, Double, Double, Double, Double, Double) {
        switch source {
        case .saved(let f): (f.caloriesPer100g, f.proteinPer100g, f.carbsPer100g, f.fatPer100g, f.fiberPer100g, f.sugarPer100g)
        case .result(let r): (r.caloriesPer100g, r.proteinPer100g, r.carbsPer100g, r.fatPer100g, r.fiberPer100g, r.sugarPer100g)
        }
    }
    private var serving: ServingOption { servings.first { $0.name == servingName } ?? servings.first ?? .gram }
    private var grams: Double { quantity * serving.grams }
    private func amount(_ per100g: Double) -> Double { per100g * grams / 100 }
    private var recentAmounts: [String] {
        if case .saved(let f) = source { return f.recentAmounts }
        return []
    }

    var body: some View {
        let p = per100
        let cal = amount(p.0), protein = amount(p.1), carbs = amount(p.2), fat = amount(p.3)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemainingHeader(profile: profile, totals: DayTotals(dayEntries), extra: (cal, protein, carbs, fat))
                Text("Previewing what's left today with this food added.")
                    .font(.caption).foregroundStyle(Theme.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.heading(24)).foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        if let brand { Text(brand) }
                        if case .saved(let f) = source, f.timesLogged > 0 {
                            Text("· logged \(f.timesLogged)×")
                        }
                        if case .result(let r) = source { Text("· \(r.sourceLabel)") }
                    }
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }

                MacroStatBox(calories: cal, protein: protein, carbs: carbs, fat: fat)

                HStack(spacing: 10) {
                    TextField("1", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title3)
                        .frame(width: 90, height: 48)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
                    Picker("Serving", selection: $servingName) {
                        ForEach(servings) { Text($0.name).tag($0.name) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder))
                }

                if !recentAmounts.isEmpty {
                    Text("MOST USED AMOUNTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recentAmounts, id: \.self) { key in
                                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                                Button {
                                    quantity = Double(parts[0]) ?? 1
                                    if parts.count > 1 { servingName = parts[1] }
                                } label: {
                                    Text(parts.count > 1 && parts[1] != servingName ? "\(parts[0]) \(parts[1])" : parts[0])
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .overlay(Capsule().stroke(key == "\(quantity.clean)|\(servingName)" ? Theme.primary : Theme.cardBorder))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    DatePicker("Time eaten", selection: $timestamp)
                    AbsorptionPicker(minutes: $absorption, manual: $absorptionManual,
                                     suggested: Absorption.suggestedMinutes(carbs: carbs, protein: protein, fat: fat))
                    Toggle("Favorite", isOn: $favorite)
                }
                .card()

                Button("Add Food") { add() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(quantity <= 0)

                NutritionList(values: [
                    ("Calories", cal, ""), ("Protein", protein, "g"), ("Carbs", carbs, "g"),
                    ("Fiber", amount(p.4), "g"), ("Sugar", amount(p.5), "g"), ("Fat", fat, "g"),
                ])
            }
            .padding()
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: grams) {
            if !absorptionManual {
                absorption = Absorption.suggestedMinutes(carbs: amount(per100.2), protein: amount(per100.1), fat: amount(per100.3))
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        timestamp = defaultTimestamp(meal: meal, date: date)
        servingName = servings.first?.name ?? "g"
        quantity = servings.first?.name == "g" ? 100 : 1
        if case .saved(let food) = source {
            favorite = food.isFavorite
            if let last = food.recentAmounts.first {
                let parts = last.split(separator: "|", maxSplits: 1).map(String.init)
                quantity = Double(parts[0]) ?? quantity
                if parts.count > 1, servings.contains(where: { $0.name == parts[1] }) { servingName = parts[1] }
            }
        }
        absorption = Absorption.suggestedMinutes(carbs: amount(per100.2), protein: amount(per100.1), fat: amount(per100.3))
    }

    private func add() {
        let food: Food
        switch source {
        case .saved(let f): food = f
        case .result(let r):
            food = r.makeFood()
            context.insert(food)
        }
        food.isFavorite = favorite
        let entry = FoodEntry(timestamp: timestamp, meal: meal, name: food.name, brand: food.brand, quantity: quantity,
                              servingName: serving.name, grams: grams, calories: 0, protein: 0, carbs: 0, fat: 0, food: food)
        entry.apply(quantity: quantity, serving: serving, from: food)
        entry.absorptionMinutes = absorption
        entry.absorptionIsManual = absorptionManual
        entry.loopStatus = entry.carbs >= 1 ? .pending : .none
        context.insert(entry)
        food.recordUse(quantity: quantity, serving: serving.name)
        try? context.save()
        onAdded()
    }
}

/// Suggested absorption time with a manual override.
struct AbsorptionPicker: View {
    @Binding var minutes: Int
    @Binding var manual: Bool
    let suggested: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Absorption time", selection: Binding(get: { minutes }, set: { minutes = $0; manual = $0 != suggested })) {
                ForEach(Array(Set(Absorption.choices + [suggested, minutes])).sorted(), id: \.self) {
                    Text(Absorption.label($0)).tag($0)
                }
            }
            Text(manual
                 ? "Suggested: \(Absorption.label(suggested)) (\(Absorption.kind(suggested).lowercased())). Tap to change back."
                 : "\(Absorption.kind(minutes)) absorption, based on the carbs, protein and fat.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .onTapGesture { if manual { minutes = suggested; manual = false } }
        }
    }
}

struct NutritionList: View {
    let values: [(String, Double, String)]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(values, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.2.isEmpty ? item.1.rounded0 : "\(item.1.rounded1) \(item.2)").monospacedDigit()
                }
                Divider()
            }
        }
        .card()
    }
}
