import SwiftUI
import SwiftData

/// Change the amount, time, meal or absorption of a logged entry.
struct EntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var entry: FoodEntry
    let profile: Profile

    @State private var quantity: Double = 1
    @State private var servingName = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MacroStatBox(calories: preview.0, protein: preview.1, carbs: preview.2, fat: preview.3)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let food = entry.food, !entry.isQuickAdd {
                    Section("Amount") {
                        HStack {
                            TextField("1", value: $quantity, format: .number).keyboardType(.decimalPad)
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $servingName) {
                                ForEach(food.allServings) { Text($0.name).tag($0.name) }
                            }
                        }
                    }
                } else {
                    Section("Nutrition") {
                        numberField("Calories", $calories)
                        numberField("Protein (g)", $protein)
                        numberField("Carbs (g)", $carbs)
                        numberField("Fat (g)", $fat)
                    }
                }
                Section {
                    DatePicker("Time eaten", selection: $entry.timestamp)
                    Picker("Meal", selection: $entry.meal) {
                        ForEach(Array(profile.mealNames.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                    }
                    AbsorptionPicker(minutes: $entry.absorptionMinutes, manual: $entry.absorptionIsManual,
                                     suggested: Absorption.suggestedMinutes(carbs: preview.2, protein: preview.1, fat: preview.3))
                }
                Section {
                    Button("Delete entry", role: .destructive) {
                        context.delete(entry)
                        dismiss()
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                quantity = entry.quantity
                servingName = entry.servingName
                calories = entry.calories; protein = entry.protein; carbs = entry.carbs; fat = entry.fat
            }
        }
    }

    private var preview: (Double, Double, Double, Double) {
        if let food = entry.food, !entry.isQuickAdd,
           let serving = food.allServings.first(where: { $0.name == servingName }) {
            let g = quantity * serving.grams
            return (food.caloriesPer100g * g / 100, food.proteinPer100g * g / 100, food.carbsPer100g * g / 100, food.fatPer100g * g / 100)
        }
        return (calories, protein, carbs, fat)
    }

    private func save() {
        if let food = entry.food, !entry.isQuickAdd,
           let serving = food.allServings.first(where: { $0.name == servingName }) {
            entry.apply(quantity: quantity, serving: serving, from: food)
        } else {
            entry.calories = calories; entry.protein = protein; entry.carbs = carbs; entry.fat = fat
            if !entry.absorptionIsManual { entry.absorptionMinutes = entry.suggestedAbsorption }
        }
        if entry.carbs >= 1 && entry.loopStatus == .none { entry.loopStatus = .pending }
        try? context.save()
        dismiss()
    }
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let profile: Profile
    let meal: Int
    let date: Date

    @State private var name = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var timestamp = Date.now
    @State private var absorption = 120
    @State private var manual = false

    private var macroCalories: Double { (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    numberField("Calories", $calories, placeholder: macroCalories > 0 ? macroCalories.rounded0 : "—")
                    numberField("Protein (g)", $protein)
                    numberField("Carbs (g)", $carbs)
                    numberField("Fat (g)", $fat)
                } footer: {
                    Text("Leave calories empty to use protein × 4 + carbs × 4 + fat × 9.")
                }
                Section {
                    DatePicker("Time eaten", selection: $timestamp)
                    AbsorptionPicker(minutes: $absorption, manual: $manual,
                                     suggested: Absorption.suggestedMinutes(carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0))
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled((calories ?? macroCalories) <= 0)
                }
            }
            .onAppear { timestamp = defaultTimestamp(meal: meal, date: date) }
            .onChange(of: [carbs, protein, fat]) {
                if !manual { absorption = Absorption.suggestedMinutes(carbs: carbs ?? 0, protein: protein ?? 0, fat: fat ?? 0) }
            }
        }
    }

    private func add() {
        let entry = FoodEntry(timestamp: timestamp, meal: meal, name: name.isEmpty ? "Quick add" : name, quantity: 1,
                              servingName: "serving", grams: 0, calories: calories ?? macroCalories,
                              protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, isQuickAdd: true)
        entry.absorptionMinutes = absorption
        entry.absorptionIsManual = manual
        entry.loopStatus = entry.carbs >= 1 ? .pending : .none
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}

/// Create a food from a nutrition label (values per serving).
struct CreateFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var barcode: String? = nil
    var onCreated: (Food) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var servingLabel = "serving"
    @State private var servingGrams: Double?
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fiber: Double?

    private var valid: Bool { !name.isEmpty && (servingGrams ?? 0) > 0 && calories != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
                Section("Serving") {
                    TextField("Label, e.g. 1 scoop", text: $servingLabel)
                    numberField("Weight (g)", $servingGrams)
                }
                Section("Per serving") {
                    numberField("Calories", $calories)
                    numberField("Protein (g)", $protein)
                    numberField("Carbs (g)", $carbs)
                    numberField("Fiber (g)", $fiber)
                    numberField("Fat (g)", $fat)
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Create food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
            }
        }
    }

    private func save() {
        guard let grams = servingGrams, grams > 0 else { return }
        let f = 100 / grams
        let food = Food(name: name, brand: brand.isEmpty ? nil : brand, source: "custom", barcode: barcode,
                        caloriesPer100g: (calories ?? 0) * f, proteinPer100g: (protein ?? 0) * f,
                        carbsPer100g: (carbs ?? 0) * f, fatPer100g: (fat ?? 0) * f, fiberPer100g: (fiber ?? 0) * f,
                        servings: [ServingOption(name: servingLabel.isEmpty ? "serving" : servingLabel, grams: grams)])
        food.isFavorite = true
        context.insert(food)
        try? context.save()
        onCreated(food)
    }
}

@ViewBuilder
func numberField(_ title: String, _ value: Binding<Double?>, placeholder: String = "—") -> some View {
    HStack {
        Text(title)
        Spacer()
        TextField(placeholder, value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
    }
}

@ViewBuilder
func numberField(_ title: String, _ value: Binding<Double>) -> some View {
    HStack {
        Text(title)
        Spacer()
        TextField("0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
    }
}
