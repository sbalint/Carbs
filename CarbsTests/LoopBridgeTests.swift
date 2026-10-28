import XCTest
@testable import Carbs

final class LoopBridgeTests: XCTestCase {
    private func entry(carbs: Double, absorption: Int, meal: Int = 1, at time: Date = .now) -> FoodEntry {
        let e = FoodEntry(timestamp: time, meal: meal, name: "Food", quantity: 1, servingName: "serving", grams: 100,
                          calories: carbs * 4, protein: 0, carbs: carbs, fat: 0)
        e.absorptionMinutes = absorption
        return e
    }

    func testMealAbsorptionIsCarbWeighted() {
        // 40 g at 60 min + 10 g at 180 min → (2400 + 1800) / 50 = 84 → 85 (nearest 5).
        XCTAssertEqual(LoopBridge.absorption(for: [entry(carbs: 40, absorption: 60), entry(carbs: 10, absorption: 180)]), 85)
    }

    func testSameMealSameDayShareAGroup() {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let a = entry(carbs: 20, absorption: 120, meal: 1, at: noon)
        let b = entry(carbs: 30, absorption: 120, meal: 1, at: noon.addingTimeInterval(1800))
        let c = entry(carbs: 30, absorption: 120, meal: 2, at: noon)
        XCTAssertEqual(LoopBridge.groupKey(for: a), LoopBridge.groupKey(for: b))
        XCTAssertNotEqual(LoopBridge.groupKey(for: a), LoopBridge.groupKey(for: c))
    }

    func testFileFormatRoundTrips() throws {
        let s = LoopMealSuggestion(id: "x", groupKey: "2026-10-28|1", mealName: "Lunch", startDate: Date(timeIntervalSince1970: 1_800_000_000),
                                   carbs: 45, absorptionMinutes: 120, foods: ["Rice"], entryIDs: ["e1"], status: .pending,
                                   updatedAt: Date(timeIntervalSince1970: 1_800_000_000), handledAt: nil)
        let data = try LoopSuggestionFile.encoder.encode(LoopSuggestionFile(suggestions: [s]))
        let decoded = try LoopSuggestionFile.decoder.decode(LoopSuggestionFile.self, from: data)
        XCTAssertEqual(decoded.suggestions, [s])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"status\" : \"pending\""))
    }
}
