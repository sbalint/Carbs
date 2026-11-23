import Foundation
import HealthKit

/// Reads steps and body measurements from Apple Health. Carbs only reads; it writes nothing to Health.
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()
    private let steps = HKQuantityType(.stepCount)
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let waist = HKQuantityType(.waistCircumference)
    private let height = HKQuantityType(.height)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet the first time; later calls return straight away.
    func requestAccess() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [steps, bodyMass, bodyFat, waist, height,
                                       HKCharacteristicType(.biologicalSex), HKCharacteristicType(.dateOfBirth)]
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    /// Step totals per day, keyed by start of day. Days without data are left out.
    func dailySteps(from start: Date, to end: Date, calendar: Calendar = .current) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        let from = calendar.startOfDay(for: start), to = calendar.startOfDay(for: end)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: steps, predicate: predicate),
            options: .cumulativeSum, anchorDate: from, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: from, to: to) { stats, _ in
            if let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                result[calendar.startOfDay(for: stats.startDate)] = sum
            }
        }
        return result
    }

    /// Average daily steps for the period and for the four weeks before it.
    func stepSummary(periodStart: Date, checkIn: Date) async -> (period: Double?, usual: Double?) {
        let before = periodStart.adding(days: -28)
        let all = await dailySteps(from: before, to: checkIn)
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let period = all.filter { $0.key >= periodStart.startOfDay }.map(\.value)
        let usual = all.filter { $0.key < periodStart.startOfDay }.map(\.value)
        // Need a few days of history before calling anything "usual".
        return (average(period), usual.count >= 7 ? average(usual) : nil)
    }

    /// Weight (lb), body fat (%) and waist (in) since `start`, the latest of each per day.
    func bodyDays(since start: Date) async -> [Date: HealthImport.Day] {
        guard isAvailable else { return [:] }
        let weights = await readings(bodyMass, unit: .pound(), since: start)
        let fats = await readings(bodyFat, unit: .percent(), since: start).map { HealthImport.Reading(date: $0.date, value: $0.value * 100) }
        let waists = await readings(waist, unit: .inch(), since: start)
        return HealthImport.days(weights: weights, bodyFat: fats, waist: waists)
    }

    struct Stats {
        var pounds: Double?
        var bodyFatPct: Double?
        var heightInches: Double?
        var sex: Sex?
        var birthYear: Int?
    }

    /// The latest of what Health knows, for filling in setup.
    func stats() async -> Stats {
        guard isAvailable else { return Stats() }
        var stats = Stats()
        stats.pounds = await latest(bodyMass, unit: .pound())
        stats.bodyFatPct = await latest(bodyFat, unit: .percent()).map { $0 * 100 }
        stats.heightInches = await latest(height, unit: .inch())
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: stats.sex = .female
        case .male: stats.sex = .male
        default: break
        }
        stats.birthYear = (try? store.dateOfBirthComponents())?.year
        return stats
    }

    private func readings(_ type: HKQuantityType, unit: HKUnit, since start: Date) async -> [HealthImport.Reading] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { .init(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func latest(_ type: HKQuantityType, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        return (try? await descriptor.result(for: store))?.first?.quantity.doubleValue(for: unit)
    }
}
