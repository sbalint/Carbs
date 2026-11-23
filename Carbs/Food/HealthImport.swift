import Foundation
import SwiftData

/// Brings weight, body fat and waist from Apple Health into the weigh-in log.
enum HealthImport {
    struct Reading: Equatable {
        let date: Date
        let value: Double
    }

    /// The latest reading of each kind on one day.
    struct Day: Equatable {
        var weight: Reading?
        var bodyFat: Reading?
        var waist: Reading?
    }

    /// Body fat and waist are often measured on a different day from weight; they join the nearest weigh-in this close.
    static let attachDays = 3

    static func days(weights: [Reading], bodyFat: [Reading], waist: [Reading], calendar: Calendar = .current) -> [Date: Day] {
        var days: [Date: Day] = [:]
        func merge(_ readings: [Reading], _ path: WritableKeyPath<Day, Reading?>) {
            for r in readings {
                let day = calendar.startOfDay(for: r.date)
                if let current = days[day]?[keyPath: path], current.date > r.date { continue }
                days[day, default: Day()][keyPath: path] = r
            }
        }
        merge(weights, \.weight)
        merge(bodyFat, \.bodyFat)
        merge(waist, \.waist)
        return days
    }

    /// Adds Health weigh-ins on days with none, updates earlier imports, and fills in body fat and waist.
    /// Values typed in Carbs always win.
    @MainActor
    static func apply(_ days: [Date: Day], to existing: [WeightLog], context: ModelContext, calendar: Calendar = .current) {
        var logs = existing
        for (day, d) in days.sorted(by: { $0.key < $1.key }) {
            guard let weight = d.weight else { continue }
            let sameDay = logs.filter { calendar.isDate($0.date, inSameDayAs: day) }
            if let log = sameDay.first(where: \.fromHealth) {
                log.date = weight.date
                log.pounds = weight.value
            } else if sameDay.isEmpty {
                let log = WeightLog(date: weight.date, pounds: weight.value, fromHealth: true)
                context.insert(log)
                logs.append(log)
            }
        }
        for (day, d) in days {
            if let fat = d.bodyFat, let log = nearest(to: day, in: logs, calendar: calendar),
               log.fromHealth || log.bodyFatPct == nil {
                log.bodyFatPct = fat.value
            }
            if let waist = d.waist, let log = nearest(to: day, in: logs, calendar: calendar),
               log.fromHealth || log.waistInches == nil {
                log.waistInches = waist.value
            }
        }
    }

    private static func nearest(to day: Date, in logs: [WeightLog], calendar: Calendar) -> WeightLog? {
        logs.map { log in (log, abs(calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: log.date)).day ?? .max)) }
            .filter { $0.1 <= attachDays }
            .min { $0.1 < $1.1 }?.0
    }

    @MainActor private static var running = false

    /// Asks for access the first time, then imports what's new since the last import (a few days of overlap catches late syncs).
    @MainActor
    static func run(profile: Profile, context: ModelContext) async {
        guard profile.healthImport, HealthService.shared.isAvailable, !running else { return }
        running = true
        defer { running = false }
        await HealthService.shared.requestAccess()
        let start = (profile.healthImportedAt?.adding(days: -attachDays) ?? min(profile.goalStartDate, .now).adding(days: -90)).startOfDay
        let days = await HealthService.shared.bodyDays(since: start)
        let window = start.adding(days: -attachDays)
        let logs = (try? context.fetch(FetchDescriptor<WeightLog>(predicate: #Predicate { $0.date >= window }))) ?? []
        apply(days, to: logs, context: context)
        // Nothing back may mean no permission yet; look back the full way next time.
        if !days.isEmpty { profile.healthImportedAt = .now }
        try? context.save()
    }
}
