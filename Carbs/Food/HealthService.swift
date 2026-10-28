import Foundation
import HealthKit

/// Reads step counts from Apple Health. Carbs only reads; it writes nothing to Health.
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()
    private let steps = HKQuantityType(.stepCount)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet the first time; later calls return straight away.
    func requestStepAccess() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [steps])
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
}
