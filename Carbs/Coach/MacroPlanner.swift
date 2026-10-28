import Foundation

enum DietType: String, Codable, CaseIterable, Identifiable {
    case balanced, lowFat, lowCarb, keto, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .lowFat: "Low fat"
        case .lowCarb: "Low carb"
        case .keto: "Keto"
        case .custom: "Custom"
        }
    }
    /// Share of the non-protein calories that go to carbs.
    var carbShare: Double? {
        switch self {
        case .balanced: 0.54
        case .lowFat: 0.70
        case .lowCarb: 0.30
        case .keto: 0.10
        case .custom: nil
        }
    }
}

struct MacroPlan: Equatable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
}

/// Protein from lean mass first, then the remaining calories split between carbs and fat.
enum MacroPlanner {
    /// Body fat assumed when none has been entered.
    static let defaultBodyFat = 25.0

    static func leanMass(weightLb: Double, bodyFatPct: Double?) -> Double {
        weightLb * (1 - (bodyFatPct ?? defaultBodyFat) / 100)
    }

    static func plan(calories: Int, weightLb: Double, bodyFatPct: Double?, proteinPerLbLBM: Double, carbShare: Double) -> MacroPlan {
        let lbm = leanMass(weightLb: weightLb, bodyFatPct: bodyFatPct)
        var protein = (lbm * proteinPerLbLBM).rounded()
        // Keep protein from taking more than 60% of calories on very low targets.
        protein = min(protein, (Double(calories) * 0.6 / 4).rounded(.down))
        let remaining = max(0, Double(calories) - protein * 4)
        let share = min(1, max(0, carbShare))
        let carbs = (remaining * share / 4).rounded()
        let fat = (remaining * (1 - share) / 9).rounded()
        return MacroPlan(calories: calories, protein: Int(protein), carbs: Int(carbs), fat: Int(fat))
    }
}
