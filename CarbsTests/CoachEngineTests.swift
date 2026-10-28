import XCTest
@testable import Carbs

final class CoachEngineTests: XCTestCase {
    let calendar = Calendar(identifier: .gregorian)

    func day(_ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d))!
    }

    /// An example week: 2050 Cal / 176 g protein a day, 220.4 → 220.0 lb,
    /// targets 2000 Cal / 180 g, goal −2.0 lb/week, maintenance estimate 2700.
    func exampleWeek(style: AdjustmentStyle, choice: TrackingChoice = .everything, calories: Double = 2050,
                     protein: Double = 176, end: Double = 220.0) -> CoachInput {
        let intake = (21...27).map { DayIntake(date: day(10, $0), calories: calories, protein: protein) }
        return CoachInput(
            periodStart: day(10, 21), checkInDate: day(10, 28), trackingChoice: choice, dailyIntake: intake,
            otherAppCalories: nil, otherAppProtein: nil,
            weights: [WeightPoint(date: day(10, 21), pounds: 220.4), WeightPoint(date: day(10, 28), pounds: end)],
            currentCalories: 2000, currentProtein: 180, goal: .fatLoss, rateLbPerWeek: 2.0, style: style,
            calorieFloor: 1500, previousTDEE: 2700, compliantStreak: 1)
    }

    func testComplianceRange() {
        XCTAssertEqual(CoachEngine.complianceRange(2000), 1940...2060)
        XCTAssertEqual(CoachEngine.complianceRange(180), 175...185)
        XCTAssertEqual(CoachEngine.complianceRange(1500), 1455...1545)
    }

    func testGentleStyleTakesSmallStep() {
        let r = CoachEngine.evaluate(exampleWeek(style: .gentle), calendar: calendar)
        XCTAssertTrue(r.compliant)
        XCTAssertEqual(r.decision, .cut)
        XCTAssertEqual(r.weightChange!, -0.4, accuracy: 0.001)
        // Burn ≈ 2700×0.6 + (2050 + 200)×0.4 = 2520; goal target 1520; the 7% cap gives 1860.
        XCTAssertEqual(r.suggestedCalories, 1860)
        XCTAssertEqual(r.newStreak, 2)
    }

    func testAggressiveStyleCutsFurther() {
        let r = CoachEngine.evaluate(exampleWeek(style: .aggressive), calendar: calendar)
        XCTAssertEqual(r.decision, .cut)
        XCTAssertEqual(r.suggestedCalories, 1700) // 15% step
    }

    func testFloorLimitsCut() {
        var input = exampleWeek(style: .aggressive)
        input.calorieFloor = 1750
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.suggestedCalories, 1750)
        XCTAssertTrue(r.floorApplied)
    }

    func testPartialTrackingHolds() {
        let r = CoachEngine.evaluate(exampleWeek(style: .aggressive, choice: .partial), calendar: calendar)
        XCTAssertEqual(r.decision, .hold)
        XCTAssertEqual(r.suggestedCalories, 2000)
        XCTAssertEqual(r.newStreak, 0)
    }

    func testOverTargetAndSlowProgressHolds() {
        let r = CoachEngine.evaluate(exampleWeek(style: .aggressive, calories: 2200), calendar: calendar)
        XCTAssertFalse(r.compliant)
        XCTAssertEqual(r.decision, .hold)
        XCTAssertEqual(r.suggestedCalories, 2000)
        XCTAssertTrue(r.message.contains("above target"))
    }

    func testOffTargetButOnTrackMatchesIntake() {
        // Ate 1800 (below range) and lost 2.4 lb: on track, so targets follow what was eaten.
        let r = CoachEngine.evaluate(exampleWeek(style: .aggressive, calories: 1800, end: 218.0), calendar: calendar)
        XCTAssertFalse(r.compliant)
        XCTAssertEqual(r.decision, .matchIntake)
        XCTAssertEqual(r.suggestedCalories, 1800)
    }

    func testFastLossRaisesCalories() {
        // Compliant and lost 4 lb in a week against a 2.0 goal.
        var input = exampleWeek(style: .gentle, end: 216.4)
        input.previousTDEE = nil
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.decision, .raise)
        XCTAssertGreaterThan(r.suggestedCalories, 2000)
    }

    func testNotEnoughLoggedDaysHolds() {
        var input = exampleWeek(style: .aggressive)
        input.dailyIntake = Array(input.dailyIntake.prefix(2))
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.decision, .hold)
    }

    func testMoreActiveWeekNudgesUp() {
        var input = exampleWeek(style: .gentle)
        // 2,000 more steps a day and one extra workout than usual, at 220 lb.
        input.activity = ActivityInput(avgSteps: 9000, baselineSteps: 7000, workouts: 4, baselineWorkouts: 3, weightLb: 220)
        let r = CoachEngine.evaluate(input, calendar: calendar)
        // Steps: 2000 × 0.04 × 220/150 = 117.3; workouts: 250/7 = 35.7; half of 153.0 → +77.
        XCTAssertEqual(r.activityAdjustment, 77)
        XCTAssertEqual(r.suggestedCalories, 1860 + 77)
        XCTAssertNotNil(r.activityNote)
    }

    func testActivityNudgeIsCapped() {
        var input = exampleWeek(style: .gentle)
        input.activity = ActivityInput(avgSteps: 4000, baselineSteps: 12000, workouts: 0, baselineWorkouts: 5, weightLb: 220)
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.activityAdjustment, -100)
    }

    func testNoBaselineMeansNoNudge() {
        var input = exampleWeek(style: .gentle)
        input.activity = ActivityInput(avgSteps: 9000, baselineSteps: nil, workouts: 4, baselineWorkouts: nil, weightLb: 220)
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.activityAdjustment, 0)
        XCTAssertEqual(r.suggestedCalories, 1860)
    }

    func testOffTargetWeekIgnoresActivity() {
        var input = exampleWeek(style: .aggressive, calories: 2200)
        input.activity = ActivityInput(avgSteps: 9000, baselineSteps: 7000, workouts: 4, baselineWorkouts: 3, weightLb: 220)
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.decision, .hold)
        XCTAssertEqual(r.suggestedCalories, 2000)
    }

    func testActivityRespectsFloor() {
        var input = exampleWeek(style: .aggressive)
        input.calorieFloor = 1650
        input.activity = ActivityInput(avgSteps: 4000, baselineSteps: 12000, workouts: nil, baselineWorkouts: nil, weightLb: 220)
        let r = CoachEngine.evaluate(input, calendar: calendar)
        // 1700 before activity; the −100 nudge stops at the 1650 floor.
        XCTAssertEqual(r.suggestedCalories, 1650)
    }

    func testThirdCompliantWeekUsesTrend() {
        var input = exampleWeek(style: .gentle)
        input.compliantStreak = 2
        input.weights = (0..<21).map { WeightPoint(date: day(10, 7).addingTimeInterval(Double($0) * 86400), pounds: 224 - Double($0) * 0.2) }
        let r = CoachEngine.evaluate(input, calendar: calendar)
        XCTAssertEqual(r.method, .trend)
    }
}

final class MacroPlannerTests: XCTestCase {
    func testBalancedSplit() {
        // 220 lb at 25% body fat → 165 lb lean mass → 182 g protein at 1.1 g/lb.
        // The other 1272 Cal split 54/46 → 172 g carbs, 65 g fat.
        let plan = MacroPlanner.plan(calories: 2000, weightLb: 220, bodyFatPct: 25, proteinPerLbLBM: 1.1, carbShare: 0.54)
        XCTAssertEqual(plan.protein, 182)
        XCTAssertEqual(plan.carbs, 172)
        XCTAssertEqual(plan.fat, 65)
    }

    func testLowerCaloriesKeepProtein() {
        let plan = MacroPlanner.plan(calories: 1800, weightLb: 220, bodyFatPct: 25, proteinPerLbLBM: 1.1, carbShare: 0.54)
        XCTAssertEqual(plan.protein, 182)
        XCTAssertEqual(plan.carbs, 145)
        XCTAssertEqual(plan.fat, 55)
    }
}

final class AbsorptionTests: XCTestCase {
    func testFastCarbs() {
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 30, protein: 0, fat: 0), 30)      // juice
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 44, protein: 4, fat: 1), 60)      // white rice
    }

    func testMixedMeal() {
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 40, protein: 30, fat: 10), 120)
    }

    func testHighFat() {
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 30, protein: 25, fat: 30), 180)   // pizza
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 60, protein: 40, fat: 50), 240)
    }

    func testNoCarbs() {
        XCTAssertEqual(Absorption.suggestedMinutes(carbs: 0, protein: 30, fat: 5), 180)
    }
}

final class TrendWeightTests: XCTestCase {
    func testTrendLagsBehindRawWeight() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let points = [WeightPoint(date: start, pounds: 240), WeightPoint(date: start.addingTimeInterval(10 * 86400), pounds: 230)]
        let series = TrendWeight.series(points, through: start.addingTimeInterval(10 * 86400), calendar: cal)
        XCTAssertEqual(series.count, 11)
        XCTAssertGreaterThan(series.last!.trend, 230)
        XCTAssertLessThan(series.last!.trend, 240)
    }
}
