import Foundation

/// The current tracking period runs from the last check-in (or goal start) to the next check-in day.
struct Period {
    var start: Date
    var checkInDate: Date

    static func current(profile: Profile, lastCheckIn: CheckIn?, calendar: Calendar = .current) -> Period {
        let start = calendar.startOfDay(for: lastCheckIn?.date ?? profile.goalStartDate)
        return Period(start: start, checkInDate: nextCheckIn(after: start, weekday: profile.checkInWeekday, calendar: calendar))
    }

    /// First day strictly after `start` that falls on `weekday`.
    static func nextCheckIn(after start: Date, weekday: Int, calendar: Calendar = .current) -> Date {
        var day = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        for _ in 0..<7 {
            if calendar.component(.weekday, from: day) == weekday { return day }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    var days: [Date] {
        let calendar = Calendar.current
        let count = max(1, calendar.dateComponents([.day], from: start, to: checkInDate).day ?? 7)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func isDue(on date: Date = .now) -> Bool {
        Calendar.current.startOfDay(for: date) >= checkInDate
    }
}

struct DayTotals {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var count: Int = 0

    init() {}

    init(_ entries: [FoodEntry]) {
        for e in entries {
            calories += e.calories
            protein += e.protein
            carbs += e.carbs
            fat += e.fat
            fiber += e.fiber
        }
        count = entries.count
    }

    /// Logged days only, keyed by start of day.
    static func byDay(_ entries: [FoodEntry], calendar: Calendar = .current) -> [Date: DayTotals] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }.mapValues(DayTotals.init)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
}
