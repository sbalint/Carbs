import Foundation

/// Weekly check-in logic. Uses a ±3% compliance band, weight
/// comparison by streak and small capped steps, and estimates burn from intake and weight change.
enum CoachEngine {
    static let caloriesPerPound = 3500.0
    /// Intake within this fraction of the target counts as on target.
    static let complianceBand = 0.03
    static let minimumLoggedDays = 4
    /// Changes smaller than this are treated as "on track".
    static let deadBand = 40.0

    static func evaluate(_ input: CoachInput, calendar: Calendar = .current) -> CoachResult {
        let start = calendar.startOfDay(for: input.periodStart)
        let checkIn = calendar.startOfDay(for: input.checkInDate)
        let periodDays = max(1, calendar.dateComponents([.day], from: start, to: checkIn).day ?? 7)
        let current = input.currentCalories

        // Average intake for the period.
        var avgCalories: Double?
        var avgProtein: Double?
        var enoughIntake = true
        switch input.trackingChoice {
        case .everything:
            let days = input.dailyIntake.filter { $0.date >= start && $0.date < checkIn }
            enoughIntake = days.count >= min(minimumLoggedDays, periodDays)
            if !days.isEmpty {
                avgCalories = days.map(\.calories).reduce(0, +) / Double(days.count)
                avgProtein = days.map(\.protein).reduce(0, +) / Double(days.count)
            }
        case .otherApp:
            avgCalories = input.otherAppCalories
            avgProtein = input.otherAppProtein ?? input.currentProtein
            enoughIntake = avgCalories != nil
        case .didntTrackMetTargets:
            avgCalories = current
            avgProtein = input.currentProtein
        case .partial:
            enoughIntake = false
        }

        let compliant: Bool = {
            guard input.trackingChoice != .partial, enoughIntake,
                  let cal = avgCalories, let protein = avgProtein else { return false }
            let range = complianceRange(current)
            let calOK = range.contains(cal.rounded())
            let proteinOK = protein.rounded() >= complianceRange(input.currentProtein).lowerBound
            return calOK && proteinOK
        }()
        let streakForMethod = compliant ? input.compliantStreak + 1 : 1
        let weight = weightChange(input.weights, start: start, checkIn: checkIn, streak: streakForMethod, calendar: calendar)
        let ratePerWeek = weight.change.map { $0 / Double(periodDays) * 7 }

        // Update the burn estimate whenever intake is actually known.
        var tdee = input.previousTDEE
        if enoughIntake, input.trackingChoice != .didntTrackMetTargets,
           let cal = avgCalories, let change = weight.change {
            let observed = min(5000, max(1200, cal - change * caloriesPerPound / Double(periodDays)))
            if let previous = input.previousTDEE {
                tdee = previous * (1 - input.style.observedWeight) + observed * input.style.observedWeight
            } else {
                tdee = observed
            }
        }

        func result(_ suggested: Double, _ decision: CoachDecision, floor: Bool, title: String, message: String) -> CoachResult {
            let rounded = Int(suggested.rounded())
            return CoachResult(
                suggestedCalories: rounded,
                change: rounded - Int(current.rounded()),
                decision: decision,
                compliant: compliant,
                newStreak: compliant ? input.compliantStreak + 1 : 0,
                method: weight.method,
                weightStart: weight.start,
                weightEnd: weight.end,
                weightChange: weight.change,
                actualRatePerWeek: ratePerWeek,
                avgCalories: avgCalories,
                avgProtein: avgProtein,
                tdeeEstimate: tdee,
                floorApplied: floor,
                title: title,
                message: message
            )
        }

        if input.trackingChoice == .partial {
            return result(current, .hold, floor: false, title: "Holding targets steady.",
                          message: "Partial logs don't show what you really ate, so your targets stay the same this week.")
        }
        guard enoughIntake, avgCalories != nil else {
            return result(current, .hold, floor: false, title: "Holding targets steady.",
                          message: "There weren't enough logged days to judge this week, so your targets stay the same.")
        }
        guard let rate = ratePerWeek, let burn = tdee else {
            return result(current, .hold, floor: false, title: "Holding targets steady.",
                          message: "Log at least two weigh-ins in a week so Carbs can see your progress.")
        }

        let goalRate = input.goal == .maintain ? 0 : input.rateLbPerWeek
        let onTrack = isOnTrack(goal: input.goal, goalRate: goalRate, actualRate: rate)

        // Off target: hold, unless progress was still on track, then match what was eaten.
        if !compliant {
            if onTrack, let cal = avgCalories {
                let (next, floor) = stepped(from: current, toward: cal, style: input.style, floor: input.calorieFloor)
                return result(next, .matchIntake, floor: floor, title: "Matching what worked.",
                              message: "Your intake was off target, but your progress was on track, so your targets now follow what you actually ate.")
            }
            return result(current, .hold, floor: false, title: "Holding targets steady.",
                          message: offTargetReason(avgCalories: avgCalories, avgProtein: avgProtein, input: input))
        }

        let goalTarget: Double = switch input.goal {
        case .fatLoss: burn - goalRate * caloriesPerPound / 7
        case .gain: burn + goalRate * caloriesPerPound / 7
        case .maintain: burn
        }
        var delta = goalTarget - current

        // Don't cut while already losing at the goal rate, or raise while still short of it.
        switch input.goal {
        case .fatLoss:
            let lossRate = -rate
            if lossRate >= goalRate * 0.9 && delta < 0 { delta = 0 }
            if lossRate <= goalRate * 1.1 && delta > 0 { delta = 0 }
        case .gain:
            if rate >= goalRate * 0.9 && delta > 0 { delta = 0 }
            if rate <= goalRate * 1.1 && delta < 0 { delta = 0 }
        case .maintain:
            if abs(rate) < 0.25 { delta = 0 }
        }

        if abs(delta) < deadBand {
            return result(current, .hold, floor: false, title: holdTitle(input.goal),
                          message: "Your progress matches your goal, so your targets stay the same.")
        }

        let (next, floor) = stepped(from: current, toward: current + delta, style: input.style, floor: input.calorieFloor)
        if Int(next.rounded()) == Int(current.rounded()) {
            return result(current, .hold, floor: floor, title: "Holding at your calorie floor.",
                          message: "Your goal rate calls for fewer calories, but you've set \(Int(input.calorieFloor)) Cal as your minimum.")
        }
        let decision: CoachDecision = next < current ? .cut : .raise
        var message = changeMessage(goal: input.goal, decision: decision, rate: rate, goalRate: goalRate)
        if floor {
            message += " Your calorie floor of \(Int(input.calorieFloor)) Cal limited this change."
        }
        return result(next, decision, floor: floor, title: changeTitle(input.goal), message: message)
    }

    // MARK: - Pieces

    /// Target ±3%, with rounded bounds (2000 → 1840–1954, 196 g → 190–202 g).
    static func complianceRange(_ target: Double) -> ClosedRange<Double> {
        (target * (1 - complianceBand)).rounded()...(target * (1 + complianceBand)).rounded()
    }

    /// Moves toward `target` by at most the style's step, never below the floor.
    static func stepped(from current: Double, toward target: Double, style: AdjustmentStyle, floor: Double) -> (Double, Bool) {
        let maxStep = current * style.maxStep
        let delta = min(maxStep, max(-maxStep, target - current))
        let next = current + delta
        // A manual target already below the floor is left alone rather than raised.
        if next < floor { return (current < floor ? current : floor, true) }
        return (next, false)
    }

    static func isOnTrack(goal: GoalType, goalRate: Double, actualRate: Double) -> Bool {
        switch goal {
        case .fatLoss: return -actualRate >= goalRate * 0.8
        case .gain: return actualRate >= goalRate * 0.8 && actualRate <= goalRate * 1.5
        case .maintain: return abs(actualRate) < 0.5
        }
    }

    struct WeightChange {
        var method: WeightMethod
        var start: Double?
        var end: Double?
        var change: Double?
    }

    static func weightChange(_ points: [WeightPoint], start: Date, checkIn: Date, streak: Int, calendar: Calendar = .current) -> WeightChange {
        let daily = TrendWeight.dailyWeights(points, calendar: calendar)
        let weekBefore = calendar.date(byAdding: .day, value: -7, to: start) ?? start

        func startEnd() -> WeightChange {
            // Start: last weigh-in on or before the period start (or the first one inside it).
            let before = daily.last { $0.date <= start }
            let inside = daily.filter { $0.date >= start && $0.date <= checkIn }
            guard let first = before ?? inside.first, let last = inside.last, last.date > first.date else {
                return WeightChange(method: .none)
            }
            return WeightChange(method: .startEnd, start: first.pounds, end: last.pounds, change: last.pounds - first.pounds)
        }

        if streak >= 3, daily.count >= 4, let first = daily.first, first.date < start {
            if let a = TrendWeight.trend(points, at: start, calendar: calendar),
               let b = TrendWeight.trend(points, at: checkIn, calendar: calendar) {
                return WeightChange(method: .trend, start: a, end: b, change: b - a)
            }
        }
        if streak >= 2 {
            let thisWeek = daily.filter { $0.date >= start && $0.date <= checkIn }.map(\.pounds)
            let lastWeek = daily.filter { $0.date >= weekBefore && $0.date < start }.map(\.pounds)
            if !thisWeek.isEmpty && !lastWeek.isEmpty {
                let a = lastWeek.reduce(0, +) / Double(lastWeek.count)
                let b = thisWeek.reduce(0, +) / Double(thisWeek.count)
                // Averages sit mid-week, so the change spans about one week.
                return WeightChange(method: .weeklyAverage, start: a, end: b, change: b - a)
            }
        }
        return startEnd()
    }

    // MARK: - Messages

    static func offTargetReason(avgCalories: Double?, avgProtein: Double?, input: CoachInput) -> String {
        var reasons: [String] = []
        if let cal = avgCalories {
            let diff = Int((cal - input.currentCalories).rounded())
            if !complianceRange(input.currentCalories).contains(cal.rounded()) {
                reasons.append(diff > 0 ? "intake averaged \(diff) Cal above target" : "intake averaged \(-diff) Cal below target")
            }
        }
        if let protein = avgProtein, protein.rounded() < complianceRange(input.currentProtein).lowerBound {
            reasons.append("protein was low")
        }
        let why = reasons.isEmpty ? "This week's intake was off target" : reasons.joined(separator: " and ").capitalizedFirst
        return "\(why), and progress didn't line up with your goal. Staying close to your current targets is the best next step before making changes."
    }

    static func holdTitle(_ goal: GoalType) -> String {
        switch goal {
        case .fatLoss: "Fat loss on track."
        case .gain: "Muscle gain on track."
        case .maintain: "Weight steady."
        }
    }

    static func changeTitle(_ goal: GoalType) -> String {
        switch goal {
        case .fatLoss: "Supporting continued fat loss."
        case .gain: "Supporting muscle gain."
        case .maintain: "Keeping your weight steady."
        }
    }

    static func changeMessage(goal: GoalType, decision: CoachDecision, rate: Double, goalRate: Double) -> String {
        let actual = String(format: "%.1f", abs(rate))
        let target = String(format: "%.1f", goalRate)
        switch (goal, decision) {
        case (.fatLoss, .cut):
            return "You lost \(actual) lb/week against a \(target) lb/week goal, so calories come down to close the gap."
        case (.fatLoss, _):
            return "You lost \(actual) lb/week, faster than your \(target) lb/week goal, so calories go up a little."
        case (.gain, .raise):
            return "You gained \(actual) lb/week against a \(target) lb/week goal, so calories go up."
        case (.gain, _):
            return "You gained faster than your \(target) lb/week goal, so calories come down a little."
        case (.maintain, _):
            return rate < 0 ? "Your weight drifted down, so calories go up." : "Your weight drifted up, so calories come down."
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
