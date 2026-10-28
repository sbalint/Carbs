import Foundation

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case fatLoss, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fatLoss: "Fat loss"
        case .maintain: "Maintenance"
        case .gain: "Build muscle"
        }
    }
}

/// How far a single check-in may move the calorie target.
enum AdjustmentStyle: String, Codable, CaseIterable, Identifiable {
    case gentle, aggressive
    var id: String { rawValue }
    var title: String { self == .gentle ? "Gentle" : "Aggressive" }
    /// Largest change per check-in, as a fraction of the current target.
    var maxStep: Double { self == .gentle ? 0.07 : 0.15 }
    /// How much weight this week's observed burn gets against the running estimate.
    var observedWeight: Double { self == .gentle ? 0.4 : 0.6 }
    var detail: String {
        self == .gentle
            ? "Changes of up to 7% per check-in."
            : "Changes of up to 15% per check-in, to reach a steep goal rate faster."
    }
}

enum TrackingChoice: String, Codable, CaseIterable, Identifiable {
    case everything, partial, didntTrackMetTargets, otherApp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everything: "I tracked everything I ate this week"
        case .partial: "I only tracked some of my meals"
        case .didntTrackMetTargets: "I didn't track, but met my targets"
        case .otherApp: "I tracked in another app"
        }
    }
    var detail: String {
        switch self {
        case .everything: "Carbs will estimate your burn and suggest new targets."
        case .partial: "Partial logs aren't enough to adjust, so targets stay the same."
        case .didntTrackMetTargets: "Carbs assumes you ate your targets this week."
        case .otherApp: "Enter your average daily calories and protein."
        }
    }
}

/// Which weight comparison the check-in used, by compliant streak.
enum WeightMethod: String, Codable {
    case startEnd, weeklyAverage, trend, none
    var title: String {
        switch self {
        case .startEnd: "start vs end of week"
        case .weeklyAverage: "this week's average vs last week's"
        case .trend: "trend weight"
        case .none: "not enough weigh-ins"
        }
    }
}

enum CoachDecision: String, Codable {
    case cut, raise, hold, matchIntake
}

struct WeightPoint: Equatable {
    var date: Date
    var pounds: Double
}

struct DayIntake: Equatable {
    var date: Date
    var calories: Double
    var protein: Double
}

struct CoachInput {
    /// First day of the period (inclusive).
    var periodStart: Date
    /// The check-in day (exclusive for intake, inclusive for the closing weigh-in).
    var checkInDate: Date
    var trackingChoice: TrackingChoice
    /// Logged days in the period. Days with nothing logged should be left out.
    var dailyIntake: [DayIntake]
    var otherAppCalories: Double?
    var otherAppProtein: Double?
    /// Full weigh-in history, any order.
    var weights: [WeightPoint]
    var currentCalories: Double
    var currentProtein: Double
    var goal: GoalType
    /// Goal rate as a positive number of pounds per week (ignored for maintenance).
    var rateLbPerWeek: Double
    var style: AdjustmentStyle
    var calorieFloor: Double
    var previousTDEE: Double?
    var compliantStreak: Int
}

struct CoachResult: Equatable {
    var suggestedCalories: Int
    var change: Int
    var decision: CoachDecision
    var compliant: Bool
    var newStreak: Int
    var method: WeightMethod
    var weightStart: Double?
    var weightEnd: Double?
    var weightChange: Double?
    /// Pounds per week; negative means losing.
    var actualRatePerWeek: Double?
    var avgCalories: Double?
    var avgProtein: Double?
    var tdeeEstimate: Double?
    var floorApplied: Bool
    var title: String
    var message: String
}
