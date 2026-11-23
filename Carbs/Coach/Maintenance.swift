import Foundation

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Female" : "Male" }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .light: "Light exercise 1–3 days a week"
        case .moderate: "Exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job plus hard training"
        }
    }

    /// Multiplier on resting energy (BMR).
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

/// Starting maintenance from body stats. Check-ins replace it with what the logs show.
enum Maintenance {
    /// Resting energy: Katch-McArdle when body fat is known, otherwise Mifflin-St Jeor.
    static func bmr(weightLb: Double, heightIn: Double, age: Int, sex: Sex, bodyFatPct: Double?) -> Double {
        let kg = weightLb * 0.453592
        if let bodyFatPct, bodyFatPct > 0 {
            return 370 + 21.6 * kg * (1 - bodyFatPct / 100)
        }
        let cm = heightIn * 2.54
        return 10 * kg + 6.25 * cm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    /// Daily maintenance calories, rounded to 10.
    static func estimate(weightLb: Double, heightIn: Double, age: Int, sex: Sex,
                         activity: ActivityLevel, bodyFatPct: Double?) -> Int {
        let tdee = bmr(weightLb: weightLb, heightIn: heightIn, age: age, sex: sex, bodyFatPct: bodyFatPct) * activity.multiplier
        return Int((tdee / 10).rounded()) * 10
    }

    /// Calories for a goal: 500 Cal a day per lb a week (3,500 Cal per lb), never below the floor.
    static func goalCalories(maintenance: Double, goal: GoalType, rateLbPerWeek: Double, floor: Double) -> Int {
        let daily: Double = switch goal {
        case .fatLoss: max(floor, maintenance - rateLbPerWeek * 500)
        case .maintain: maintenance
        case .gain: maintenance + rateLbPerWeek * 500
        }
        return Int((daily / 10).rounded()) * 10
    }
}
