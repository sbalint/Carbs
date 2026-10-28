#if DEBUG
import Foundation
import SwiftData

/// Sample data for Simulator screenshots. Launch with `-demo` (and optionally `-tab N`).
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard isEnabled, (try? context.fetchCount(FetchDescriptor<Profile>())) == 0 else { return }
        let today = Date.now.startOfDay
        let profile = Profile()
        profile.goalStartDate = today.adding(days: -6)
        profile.startWeight = 228.0
        profile.goalWeight = 215
        profile.rateLbPerWeek = 2.5
        profile.checkInWeekday = Calendar.current.component(.weekday, from: today.adding(days: 1))
        profile.calories = 1860
        profile.tdeeEstimate = 2600
        profile.proteinPerLbLBM = 1.13
        profile.replanMacros(weightLb: 220.0, bodyFatPct: 25.0)
        context.insert(profile)

        for d in 0..<21 {
            let w = 238.5 - Double(d) * 0.13 + (d % 3 == 0 ? 0.6 : d % 3 == 1 ? -0.3 : 0)
            context.insert(WeightLog(date: today.adding(days: -20 + d).addingTimeInterval(7 * 3600), pounds: w,
                                     bodyFatPct: d == 20 ? 25.0 : nil))
        }

        let shake = Food(name: "Protein Isolate", brand: "Demo", caloriesPer100g: 375, proteinPer100g: 75,
                         carbsPer100g: 12.5, fatPer100g: 3.75, servings: [ServingOption(name: "scoop", grams: 40)])
        let rice = Food(name: "White Rice, cooked", source: "usda", caloriesPer100g: 130, proteinPer100g: 2.7,
                        carbsPer100g: 28.2, fatPer100g: 0.3, servings: [ServingOption(name: "cup", grams: 158)])
        let chicken = Food(name: "Chicken Thighs, boneless", caloriesPer100g: 177, proteinPer100g: 24,
                           carbsPer100g: 0, fatPer100g: 9.6, servings: [ServingOption(name: "thigh", grams: 62)])
        let pizza = Food(name: "Pepperoni Pizza", source: "usda", caloriesPer100g: 298, proteinPer100g: 12.6,
                         carbsPer100g: 30.5, fatPer100g: 13.6, servings: [ServingOption(name: "slice", grams: 107)])
        [shake, rice, chicken, pizza].forEach { context.insert($0); $0.isFavorite = $0 === shake }

        for d in 0..<7 {
            let day = today.adding(days: -6 + d)
            func add(_ food: Food, _ q: Double, _ meal: Int, _ hour: Int) {
                let serving = food.servings[0]
                let e = FoodEntry(timestamp: day.addingTimeInterval(Double(hour) * 3600), meal: meal, name: food.name,
                                  brand: food.brand, quantity: q, servingName: serving.name, grams: 0,
                                  calories: 0, protein: 0, carbs: 0, fat: 0, food: food)
                e.apply(quantity: q, serving: serving, from: food)
                context.insert(e)
                food.recordUse(quantity: q, serving: serving.name)
            }
            add(shake, 1.5, 0, 8)
            add(rice, 1, 1, 12)
            add(chicken, 3, 1, 12)
            if d < 6 { add(pizza, 2, 2, 18); add(chicken, 2, 2, 18) }
        }
        try? context.save()
    }
}
#endif
