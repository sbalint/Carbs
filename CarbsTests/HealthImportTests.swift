import XCTest
import SwiftData
@testable import Carbs

@MainActor
final class HealthImportTests: XCTestCase {
    private let today = Calendar.current.startOfDay(for: .now)
    private var context: ModelContext!

    override func setUp() async throws {
        let container = try ModelContainer(for: WeightLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func at(_ daysAgo: Int, hour: Int = 7) -> Date {
        today.adding(days: -daysAgo).addingTimeInterval(Double(hour) * 3600)
    }

    private func logs() throws -> [WeightLog] {
        try context.fetch(FetchDescriptor<WeightLog>(sortBy: [SortDescriptor(\.date)]))
    }

    func testLatestReadingPerDay() {
        let days = HealthImport.days(weights: [.init(date: at(0, hour: 7), value: 200), .init(date: at(0, hour: 20), value: 202)],
                                     bodyFat: [], waist: [])
        XCTAssertEqual(days[today]?.weight?.value, 202)
    }

    func testAddsWeighInsAndKeepsTypedOnes() throws {
        context.insert(WeightLog(date: at(1), pounds: 210))
        let days = HealthImport.days(weights: [.init(date: at(1), value: 205), .init(date: at(0), value: 204)], bodyFat: [], waist: [])
        HealthImport.apply(days, to: try logs(), context: context)
        let all = try logs()
        XCTAssertEqual(all.map(\.pounds), [210, 204])
        XCTAssertEqual(all.map(\.fromHealth), [false, true])
    }

    func testUpdatesEarlierImport() throws {
        context.insert(WeightLog(date: at(0, hour: 6), pounds: 205, fromHealth: true))
        let days = HealthImport.days(weights: [.init(date: at(0, hour: 9), value: 204.4)], bodyFat: [], waist: [])
        HealthImport.apply(days, to: try logs(), context: context)
        XCTAssertEqual(try logs().map(\.pounds), [204.4])
    }

    func testMeasurementsJoinNearestWeighIn() throws {
        context.insert(WeightLog(date: at(5), pounds: 210))
        context.insert(WeightLog(date: at(1), pounds: 208, bodyFatPct: 24))
        // Waist two days after the first weigh-in, body fat on the day of the second, waist far from any weigh-in.
        let days = HealthImport.days(weights: [],
                                     bodyFat: [.init(date: at(1), value: 22)],
                                     waist: [.init(date: at(3, hour: 6), value: 40), .init(date: at(20), value: 42)])
        HealthImport.apply(days, to: try logs(), context: context)
        let all = try logs()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].waistInches, 40)
        XCTAssertEqual(all[1].bodyFatPct, 24, "Typed body fat is kept")
        XCTAssertNil(all[1].waistInches)
    }
}
