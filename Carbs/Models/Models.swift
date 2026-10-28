import Foundation
import SwiftData

struct ServingOption: Codable, Hashable, Identifiable {
    var name: String
    var grams: Double
    var id: String { name }

    static let gram = ServingOption(name: "g", grams: 1)
    static let ounce = ServingOption(name: "oz", grams: 28.3495)
}

/// A food that can be logged: from a database lookup, created by hand, or a quick add.
@Model
final class Food {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    /// "openfoodfacts", "usda", "custom"
    var source: String = "custom"
    var sourceID: String?
    var barcode: String?
    var caloriesPer100g: Double = 0
    var proteinPer100g: Double = 0
    var carbsPer100g: Double = 0
    var fatPer100g: Double = 0
    var fiberPer100g: Double = 0
    var sugarPer100g: Double = 0
    var servings: [ServingOption] = []
    var isFavorite: Bool = false
    var timesLogged: Int = 0
    var lastUsed: Date?
    /// Recent amounts as "quantity|serving", most recent first.
    var recentAmounts: [String] = []

    init(name: String, brand: String? = nil, source: String = "custom", sourceID: String? = nil, barcode: String? = nil,
         caloriesPer100g: Double, proteinPer100g: Double, carbsPer100g: Double, fatPer100g: Double,
         fiberPer100g: Double = 0, sugarPer100g: Double = 0, servings: [ServingOption] = []) {
        self.name = name
        self.brand = brand
        self.source = source
        self.sourceID = sourceID
        self.barcode = barcode
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.servings = servings
    }

    var allServings: [ServingOption] {
        var list = servings
        for base in [ServingOption.gram, .ounce] where !list.contains(where: { $0.name == base.name }) {
            list.append(base)
        }
        return list
    }

    func recordUse(quantity: Double, serving: String) {
        timesLogged += 1
        lastUsed = .now
        let key = "\(quantity.clean)|\(serving)"
        recentAmounts.removeAll { $0 == key }
        recentAmounts.insert(key, at: 0)
        recentAmounts = Array(recentAmounts.prefix(5))
    }
}

/// Where an entry stands with Loop. Carbs never writes carbs to Apple Health.
enum LoopStatus: String, Codable {
    case none, pending, accepted, dismissed
}

@Model
final class FoodEntry {
    var id: UUID = UUID()
    /// When the food was eaten. Loop uses this as the carb entry time.
    var timestamp: Date = Date.now
    var meal: Int = 0
    var name: String = ""
    var brand: String?
    var quantity: Double = 1
    var servingName: String = "serving"
    var grams: Double = 0
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var absorptionMinutes: Int = 120
    var absorptionIsManual: Bool = false
    var loopStatusRaw: String = LoopStatus.none.rawValue
    var isQuickAdd: Bool = false
    var food: Food?

    init(timestamp: Date, meal: Int, name: String, brand: String? = nil, quantity: Double, servingName: String, grams: Double,
         calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 0, food: Food? = nil, isQuickAdd: Bool = false) {
        self.timestamp = timestamp
        self.meal = meal
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.servingName = servingName
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.food = food
        self.isQuickAdd = isQuickAdd
        self.absorptionMinutes = Absorption.suggestedMinutes(carbs: carbs, protein: protein, fat: fat)
    }

    var loopStatus: LoopStatus {
        get { LoopStatus(rawValue: loopStatusRaw) ?? .none }
        set { loopStatusRaw = newValue.rawValue }
    }

    var suggestedAbsorption: Int { Absorption.suggestedMinutes(carbs: carbs, protein: protein, fat: fat) }

    /// Rescales nutrition for a new amount of the linked food.
    func apply(quantity: Double, serving: ServingOption, from food: Food) {
        self.quantity = quantity
        self.servingName = serving.name
        let g = quantity * serving.grams
        grams = g
        calories = food.caloriesPer100g * g / 100
        protein = food.proteinPer100g * g / 100
        carbs = food.carbsPer100g * g / 100
        fat = food.fatPer100g * g / 100
        fiber = food.fiberPer100g * g / 100
        if !absorptionIsManual { absorptionMinutes = suggestedAbsorption }
    }
}

@Model
final class WeightLog {
    var id: UUID = UUID()
    var date: Date = Date.now
    var pounds: Double = 0
    var bodyFatPct: Double?
    var note: String?

    init(date: Date, pounds: Double, bodyFatPct: Double? = nil) {
        self.date = date
        self.pounds = pounds
        self.bodyFatPct = bodyFatPct
    }
}

@Model
final class CheckIn {
    var id: UUID = UUID()
    var date: Date = Date.now
    var periodStart: Date = Date.now
    var trackingChoiceRaw: String = TrackingChoice.everything.rawValue
    var methodRaw: String = WeightMethod.none.rawValue
    var decisionRaw: String = CoachDecision.hold.rawValue
    var avgCalories: Double?
    var avgProtein: Double?
    var weightStart: Double?
    var weightEnd: Double?
    var weightChange: Double?
    var actualRatePerWeek: Double?
    var tdeeEstimate: Double?
    var previousCalories: Int = 0
    var previousProtein: Int = 0
    var suggestedCalories: Int = 0
    /// What the user chose: the suggestion or their own number.
    var acceptedCalories: Int = 0
    var protein: Int = 0
    var carbs: Int = 0
    var fat: Int = 0
    var compliant: Bool = false
    var floorApplied: Bool = false
    var title: String = ""
    var message: String = ""
    var note: String?
    var avgSteps: Double?
    var usualSteps: Double?
    var workouts: Int?
    var activityAdjustment: Int = 0

    init(date: Date, periodStart: Date) {
        self.date = date
        self.periodStart = periodStart
    }

    var trackingChoice: TrackingChoice { TrackingChoice(rawValue: trackingChoiceRaw) ?? .everything }
    var method: WeightMethod { WeightMethod(rawValue: methodRaw) ?? .none }
    var decision: CoachDecision { CoachDecision(rawValue: decisionRaw) ?? .hold }
    var change: Int { acceptedCalories - previousCalories }
    var followedSuggestion: Bool { acceptedCalories == suggestedCalories }
}

/// The single settings and goal record.
@Model
final class Profile {
    var createdAt: Date = Date.now
    var goalTypeRaw: String = GoalType.fatLoss.rawValue
    var goalStartDate: Date = Date.now
    var startWeight: Double = 0
    var goalWeight: Double = 0
    var rateLbPerWeek: Double = 1.0
    /// 1 = Sunday … 7 = Saturday
    var checkInWeekday: Int = 4
    var styleRaw: String = AdjustmentStyle.aggressive.rawValue
    var calorieFloor: Double = 1500
    var calories: Int = 2000
    var protein: Int = 150
    var carbs: Int = 200
    var fat: Int = 60
    var useCustomMacros: Bool = false
    var proteinPerLbLBM: Double = 1.1
    var dietTypeRaw: String = DietType.balanced.rawValue
    var carbShare: Double = 0.54
    var tdeeEstimate: Double?
    var compliantStreak: Int = 0
    var mealNames: [String] = ["Breakfast", "Lunch", "Dinner", "Snack"]
    var usdaAPIKey: String = ""

    init() {}

    var goalType: GoalType {
        get { GoalType(rawValue: goalTypeRaw) ?? .fatLoss }
        set { goalTypeRaw = newValue.rawValue }
    }
    var style: AdjustmentStyle {
        get { AdjustmentStyle(rawValue: styleRaw) ?? .aggressive }
        set { styleRaw = newValue.rawValue }
    }
    var dietType: DietType {
        get { DietType(rawValue: dietTypeRaw) ?? .balanced }
        set {
            dietTypeRaw = newValue.rawValue
            if let share = newValue.carbShare { carbShare = share }
        }
    }

    /// Recomputes protein, carbs and fat for the current calorie target.
    func replanMacros(weightLb: Double, bodyFatPct: Double?) {
        guard !useCustomMacros else { return }
        let plan = MacroPlanner.plan(calories: calories, weightLb: weightLb, bodyFatPct: bodyFatPct,
                                     proteinPerLbLBM: proteinPerLbLBM, carbShare: carbShare)
        protein = plan.protein
        carbs = plan.carbs
        fat = plan.fat
    }
}

extension Double {
    /// "1", "1.5", "0.25" — no trailing zeros.
    var clean: String {
        let rounded = (self * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }
}
