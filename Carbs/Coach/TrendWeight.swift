import Foundation

/// Exponentially smoothed weight, one step per calendar day. Missing days are filled by
/// straight-line interpolation between weigh-ins.
enum TrendWeight {
    static let alpha = 0.1

    /// Daily trend values from the first weigh-in through `end`, keyed by start of day.
    static func series(_ points: [WeightPoint], through end: Date, calendar: Calendar = .current) -> [(date: Date, trend: Double)] {
        let daily = dailyWeights(points, calendar: calendar)
        guard let first = daily.first else { return [] }
        let endDay = calendar.startOfDay(for: end)
        var result: [(Date, Double)] = []
        var trend = first.pounds
        var day = first.date
        var index = 0
        while day <= endDay {
            // Find the bracketing weigh-ins for this day.
            while index + 1 < daily.count && daily[index + 1].date <= day { index += 1 }
            let value: Double
            if daily[index].date == day || index + 1 >= daily.count {
                value = daily[index].pounds
            } else {
                let a = daily[index], b = daily[index + 1]
                let span = b.date.timeIntervalSince(a.date)
                let t = span > 0 ? day.timeIntervalSince(a.date) / span : 0
                value = a.pounds + (b.pounds - a.pounds) * t
            }
            trend = day == first.date ? value : trend + alpha * (value - trend)
            result.append((day, trend))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func trend(_ points: [WeightPoint], at date: Date, calendar: Calendar = .current) -> Double? {
        series(points, through: date, calendar: calendar).last?.trend
    }

    /// One value per day (the day's average), sorted.
    static func dailyWeights(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        let grouped = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { WeightPoint(date: $0.key, pounds: $0.value.map(\.pounds).reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }
}
