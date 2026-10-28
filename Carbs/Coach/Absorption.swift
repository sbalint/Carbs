import Foundation

/// Suggested carb absorption time for Loop, from what the food is made of.
/// Mostly carbs: 30–60 min. Mixed: 120 min. High fat: 180+ min.
enum Absorption {
    static let choices = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    static func suggestedMinutes(carbs: Double, protein: Double, fat: Double) -> Int {
        let carbCal = carbs * 4, proteinCal = protein * 4, fatCal = fat * 9
        let total = carbCal + proteinCal + fatCal
        guard total > 0, carbs > 0 else { return 180 }
        let carbShare = carbCal / total
        let fatShare = fatCal / total

        if fatShare >= 0.40 || (fat >= 25 && carbShare < 0.5) {
            return fat >= 40 ? 240 : 180
        }
        if carbShare >= 0.9 { return 30 }
        if carbShare >= 0.7 && fatShare <= 0.15 { return 60 }
        return 120
    }

    static func label(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }

    static func kind(_ minutes: Int) -> String {
        switch minutes {
        case ..<75: "Fast"
        case ..<165: "Medium"
        default: "Slow"
        }
    }
}
