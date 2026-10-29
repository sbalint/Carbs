import XCTest
@testable import Carbs

final class MaintenanceTests: XCTestCase {
    func testMifflinStJeor() {
        // 220 lb, 5'10", 40, male, lightly active: BMR 1914 × 1.375
        XCTAssertEqual(Maintenance.estimate(weightLb: 220, heightIn: 70, age: 40, sex: .male, activity: .light, bodyFatPct: nil), 2630)
        // 150 lb, 5'5", 30, female, sedentary: BMR 1401 × 1.2
        XCTAssertEqual(Maintenance.estimate(weightLb: 150, heightIn: 65, age: 30, sex: .female, activity: .sedentary, bodyFatPct: nil), 1680)
    }

    func testBodyFatUsesLeanMass() {
        // 165 lb lean mass: 370 + 21.6 × 74.8 kg = 1987 × 1.375
        XCTAssertEqual(Maintenance.estimate(weightLb: 220, heightIn: 70, age: 40, sex: .male, activity: .light, bodyFatPct: 25), 2730)
    }

    func testGoalCalories() {
        XCTAssertEqual(Maintenance.goalCalories(maintenance: 2700, goal: .fatLoss, rateLbPerWeek: 2, floor: 1500), 1700)
        XCTAssertEqual(Maintenance.goalCalories(maintenance: 2700, goal: .fatLoss, rateLbPerWeek: 2, floor: 1800), 1800)
        XCTAssertEqual(Maintenance.goalCalories(maintenance: 2700, goal: .maintain, rateLbPerWeek: 2, floor: 1500), 2700)
        XCTAssertEqual(Maintenance.goalCalories(maintenance: 2700, goal: .gain, rateLbPerWeek: 0.5, floor: 1500), 2950)
    }
}

final class MealSuggestionsTests: XCTestCase {
    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: .now)
    private let coffee = UUID(), toast = UUID(), cake = UUID()

    private func use(_ food: UUID, daysAgo: Int, quantity: Double = 1, serving: String = "serving") -> MealSuggestions.Use {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return .init(foodID: food, timestamp: day.addingTimeInterval(8 * 3600), quantity: quantity, servingName: serving)
    }

    func testRegularFoodsAreSuggestedWithLatestAmount() {
        let history = [use(coffee, daysAgo: 3), use(coffee, daysAgo: 2), use(coffee, daysAgo: 1, quantity: 0.8),
                       use(toast, daysAgo: 2), use(toast, daysAgo: 1),
                       use(cake, daysAgo: 1)]
        let picks = MealSuggestions.suggest(history: history, before: today, excluding: [])
        XCTAssertEqual(picks.map(\.foodID), [coffee, toast])
        XCTAssertEqual(picks.first?.quantity, 0.8)
    }

    func testAlreadyLoggedAndOldFoodsAreSkipped() {
        let history = [use(coffee, daysAgo: 2), use(coffee, daysAgo: 1),
                       use(toast, daysAgo: 20), use(toast, daysAgo: 19)]
        XCTAssertTrue(MealSuggestions.suggest(history: history, before: today, excluding: [coffee]).isEmpty)
    }

    func testRareFoodsAreSkipped() {
        // Cake on 2 of 10 breakfasts is under 30%.
        var history = (1...10).map { use(coffee, daysAgo: $0) }
        history += [use(cake, daysAgo: 4), use(cake, daysAgo: 9)]
        XCTAssertEqual(MealSuggestions.suggest(history: history, before: today, excluding: []).map(\.foodID), [coffee])
    }
}
