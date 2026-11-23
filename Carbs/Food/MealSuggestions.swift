import Foundation

/// Foods that keep turning up in the same meal, offered as one-tap adds.
enum MealSuggestions {
    /// One past use of a food in the meal.
    struct Use {
        let foodID: UUID
        let timestamp: Date
        let quantity: Double
        let servingName: String
    }

    struct Pick: Equatable {
        let foodID: UUID
        let quantity: Double
        let servingName: String
    }

    /// Looks back `lookbackDays` before `date`. A food qualifies when it was in this meal on at least
    /// two days and on at least 30% of the days the meal was logged. Uses the most recent amount.
    static func suggest(history: [Use], before date: Date, excluding logged: Set<UUID>,
                        lookbackDays: Int = 14, limit: Int = 5, calendar: Calendar = .current) -> [Pick] {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) else { return [] }
        let recent = history.filter { $0.timestamp >= start && $0.timestamp < end }
        let mealDays = Set(recent.map { calendar.startOfDay(for: $0.timestamp) }).count
        guard mealDays > 0 else { return [] }

        let candidates = Dictionary(grouping: recent, by: \.foodID).compactMap { id, uses -> (Pick, Int, Date)? in
            guard !logged.contains(id) else { return nil }
            let days = Set(uses.map { calendar.startOfDay(for: $0.timestamp) }).count
            guard days >= 2, Double(days) >= Double(mealDays) * 0.3,
                  let latest = uses.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return (Pick(foodID: id, quantity: latest.quantity, servingName: latest.servingName), days, latest.timestamp)
        }
        return candidates
            .sorted { ($0.1, $0.2) > ($1.1, $1.2) }
            .prefix(limit)
            .map(\.0)
    }
}
