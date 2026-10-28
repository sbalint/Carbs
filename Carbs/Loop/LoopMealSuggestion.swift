import Foundation

// Shared with Loop (sbalint/Loop, branch carbs-next-dev, Loop/Models/CarbsMealSuggestion.swift).
// Keep the two copies of the file format in step.

/// A meal Carbs offers to Loop. Loop never saves it on its own: it opens its normal carb entry
/// screen filled in with these values, and the user confirms there.
struct LoopMealSuggestion: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        /// Waiting for the user in Loop.
        case pending
        /// Opened in Loop's carb entry screen (the user may still have cancelled there).
        case reviewed
        /// Dismissed in Loop without opening.
        case dismissed
    }

    var id: String
    /// Day and meal, e.g. "2026-10-28|1", so later edits to the same meal update this suggestion.
    var groupKey: String
    var mealName: String
    /// When the meal was eaten: the earliest entry's time.
    var startDate: Date
    var carbs: Double
    var absorptionMinutes: Int
    var foods: [String]
    var entryIDs: [String]
    var status: Status
    var updatedAt: Date
    var handledAt: Date?
}

struct LoopSuggestionFile: Codable {
    var version = 1
    var suggestions: [LoopMealSuggestion] = []

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
