import SwiftUI
import SwiftData

/// Weekly check-in: tracking, metrics, review, then a suggested target you can accept or change.
struct CheckInFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var profile: Profile
    let period: Period
    let entries: [FoodEntry]
    let weights: [WeightLog]
    let lastCheckIn: CheckIn?

    @State private var step = 1
    @State private var choice: TrackingChoice = .everything
    @State private var otherCalories: Double?
    @State private var otherProtein: Double?
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var draft: CheckIn?
    @State private var plan: MacroPlan?
    @State private var useOwn = false
    @State private var ownCalories: Int?

    private var today: Date { Date.now.startOfDay }
    private var todaysLog: WeightLog? { weights.last { $0.date.startOfDay == today } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step <= 3 {
                        ProgressView(value: Double(step), total: 3).tint(Theme.primary)
                        Text("Step \(step) of 3").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    switch step {
                    case 1: trackingStep
                    case 2: metricsStep
                    case 3: reviewStep
                    default: reportStep
                    }
                }
                .padding()
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) { bottomButton.padding() }
            .keyboardDoneButton()
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                if step > 1 && step <= 3 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { step -= 1 } label: { Image(systemName: "chevron.left") }
                    }
                }
            }
            .onAppear {
                weight = todaysLog?.pounds
                bodyFat = todaysLog?.bodyFatPct ?? weights.last(where: { $0.bodyFatPct != nil })?.bodyFatPct
            }
        }
    }

    // MARK: Steps

    private var trackingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your tracking").font(.heading(24))
            Text("Which option best describes how you tracked this period?").foregroundStyle(Theme.secondaryText)
            ForEach(TrackingChoice.allCases) { option in
                Button { choice = option } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).foregroundStyle(Theme.text)
                                Text(option.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: choice == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(choice == option ? Theme.primary : Theme.secondaryText)
                        }
                        if choice == option && option == .everything { consumption }
                        if choice == option && option == .otherApp {
                            numberField("Average calories", $otherCalories)
                            numberField("Average protein (g)", $otherProtein)
                        }
                    }
                    .card()
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(choice == option ? Theme.primary : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var consumption: some View {
        let days = DayTotals.byDay(entries.filter { $0.timestamp < today })
        let n = Double(max(1, days.count))
        let avg = days.values.reduce(DayTotals()) { acc, t in
            var a = acc; a.calories += t.calories; a.protein += t.protein; a.carbs += t.carbs; a.fat += t.fat; return a
        }
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("Average over \(days.count) logged day\(days.count == 1 ? "" : "s")").font(.caption)
                Spacer()
                Text("\((avg.calories / n).rounded0) Cal").font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 12) {
                macro("P", avg.protein / n, Double(profile.protein), Theme.protein)
                macro("C", avg.carbs / n, Double(profile.carbs), Theme.carbs)
                macro("F", avg.fat / n, Double(profile.fat), Theme.fat)
            }
        }
    }

    private func macro(_ label: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(label) \(value.rounded0)g").font(.caption)
            MacroBar(value: value, target: target, color: color)
        }
    }

    private var metricsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your metrics").font(.heading(24))
            Text("Today's weight is used to measure progress over time.").foregroundStyle(Theme.secondaryText)
            VStack(spacing: 12) {
                numberField("Weight (lb)", $weight)
                numberField("Body fat % (optional)", $bodyFat)
            }
            .card()
            Label("Daily weight swings with water, salt and timing. Weighing in most days lets Carbs see the trend.", systemImage: "lightbulb")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final review").font(.heading(24))
            VStack(alignment: .leading, spacing: 10) {
                row("Tracking", choice == .everything ? "Complete" : choice == .partial ? "Partial" : choice == .otherApp ? "Other app" : "Not tracked")
                row("Today's weight", weight.map { "\($0.rounded1) lbs" } ?? "—")
                row("Body fat", bodyFat.map { "\($0.rounded1)%" } ?? "—")
                row("Adjustment style", profile.style.title)
            }
            .card()
            Text("Carbs looks at patterns over weeks, not single days. You can still change the suggested target on the next screen.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(Theme.secondaryText) }
    }

    @ViewBuilder
    private var reportStep: some View {
        if let draft, let plan {
            CheckInReportView(checkIn: draft, preview: plan)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your calorie target").font(.headline)
                Picker("", selection: $useOwn) {
                    Text("Use \(draft.suggestedCalories) Cal").tag(false)
                    Text("Set my own").tag(true)
                }
                .pickerStyle(.segmented)
                if useOwn {
                    HStack {
                        TextField("\(draft.suggestedCalories)", value: $ownCalories, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title2.weight(.semibold))
                        Text("Cal").foregroundStyle(Theme.secondaryText)
                    }
                    Text("Protein stays at \(plan.protein) g; carbs and fat are split from the rest.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        switch step {
        case 1:
            Button("Next") { step = 2 }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(choice == .otherApp && otherCalories == nil)
        case 2:
            Button("Next") { step = 3 }.buttonStyle(PrimaryButtonStyle()).disabled(weight == nil)
        case 3:
            Button("Submit") { evaluate(); step = 4 }.buttonStyle(PrimaryButtonStyle())
        default:
            Button("Let's go!") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(useOwn && (ownCalories ?? 0) < 800)
        }
    }

    // MARK: Logic

    private func evaluate() {
        var points = weights.map { WeightPoint(date: $0.date, pounds: $0.pounds) }
        if let weight {
            points.removeAll { $0.date.startOfDay == today }
            points.append(WeightPoint(date: .now, pounds: weight))
        }
        let days = DayTotals.byDay(entries.filter { $0.timestamp < today })
            .map { DayIntake(date: $0.key, calories: $0.value.calories, protein: $0.value.protein) }
        let input = CoachInput(
            periodStart: period.start, checkInDate: today, trackingChoice: choice, dailyIntake: days,
            otherAppCalories: otherCalories, otherAppProtein: otherProtein, weights: points,
            currentCalories: Double(profile.calories), currentProtein: Double(profile.protein),
            goal: profile.goalType, rateLbPerWeek: profile.rateLbPerWeek, style: profile.style,
            calorieFloor: profile.calorieFloor, previousTDEE: profile.tdeeEstimate,
            compliantStreak: profile.compliantStreak)
        let r = CoachEngine.evaluate(input)

        let c = CheckIn(date: .now, periodStart: period.start)
        c.trackingChoiceRaw = choice.rawValue
        c.methodRaw = r.method.rawValue
        c.decisionRaw = r.decision.rawValue
        c.avgCalories = r.avgCalories
        c.avgProtein = r.avgProtein
        c.weightStart = r.weightStart
        c.weightEnd = r.weightEnd
        c.weightChange = r.weightChange
        c.actualRatePerWeek = r.actualRatePerWeek
        c.tdeeEstimate = r.tdeeEstimate
        c.previousCalories = profile.calories
        c.previousProtein = profile.protein
        c.suggestedCalories = r.suggestedCalories
        c.acceptedCalories = r.suggestedCalories
        c.compliant = r.compliant
        c.floorApplied = r.floorApplied
        c.title = r.title
        c.message = r.message
        draft = c
        plan = macroPlan(for: r.suggestedCalories)
        ownCalories = r.suggestedCalories
    }

    private func macroPlan(for calories: Int) -> MacroPlan {
        MacroPlanner.plan(calories: calories, weightLb: weight ?? profile.startWeight, bodyFatPct: bodyFat,
                          proteinPerLbLBM: profile.proteinPerLbLBM, carbShare: profile.carbShare)
    }

    private func save() {
        guard let draft else { return }
        if let weight {
            if let log = todaysLog {
                log.pounds = weight
                log.bodyFatPct = bodyFat
            } else {
                context.insert(WeightLog(date: .now, pounds: weight, bodyFatPct: bodyFat))
            }
        }
        let chosen = useOwn ? (ownCalories ?? draft.suggestedCalories) : draft.suggestedCalories
        let finalPlan = macroPlan(for: chosen)
        draft.acceptedCalories = chosen
        draft.protein = finalPlan.protein
        draft.carbs = finalPlan.carbs
        draft.fat = finalPlan.fat
        context.insert(draft)

        profile.calories = chosen
        if !profile.useCustomMacros {
            profile.protein = finalPlan.protein
            profile.carbs = finalPlan.carbs
            profile.fat = finalPlan.fat
        }
        if let tdee = draft.tdeeEstimate { profile.tdeeEstimate = tdee }
        profile.compliantStreak = draft.compliant ? profile.compliantStreak + 1 : 0
        try? context.save()
        dismiss()
    }
}

/// The check-in report, used right after a check-in and from the history list.
struct CheckInReportView: View {
    let checkIn: CheckIn
    var preview: MacroPlan? = nil

    var body: some View {
        let macros = preview ?? MacroPlan(calories: checkIn.acceptedCalories, protein: checkIn.protein, carbs: checkIn.carbs, fat: checkIn.fat)
        let change = preview == nil ? checkIn.change : checkIn.suggestedCalories - checkIn.previousCalories
        VStack(alignment: .leading, spacing: 14) {
            Label("Check-in Report", systemImage: "checklist").font(.heading(24))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(change == 0 ? "Macros unchanged" : preview == nil ? "Macro targets" : "Suggested targets").font(.headline)
                        Text(preview == nil && !checkIn.followedSuggestion
                             ? "You set this target yourself (suggested \(checkIn.suggestedCalories) Cal)."
                             : "Starting today.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if change != 0 {
                        Text(String(format: "%+d Cal", change))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.primary.opacity(0.15), in: Capsule())
                    }
                }
                MacroStatBox(calories: Double(preview?.calories ?? macros.calories), protein: Double(macros.protein),
                             carbs: Double(macros.carbs), fat: Double(macros.fat))
                VStack(alignment: .leading, spacing: 6) {
                    Text(checkIn.title).font(.subheadline.weight(.semibold))
                    Text(checkIn.message).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            .card()

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    if let s = checkIn.weightStart, let e = checkIn.weightEnd, let c = checkIn.weightChange {
                        Text("Weight went from \(s.rounded1) to \(e.rounded1) lb (\(String(format: "%+.1f", c)) lb), using \(checkIn.method.title).")
                    }
                    if let r = checkIn.actualRatePerWeek { Text("That's \(String(format: "%+.2f", r)) lb/week.") }
                }
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            } label: {
                Label(weightLabel, systemImage: "scalemass")
            }
            .card()

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    if let cal = checkIn.avgCalories {
                        Text("You averaged \(cal.rounded0) Cal and \((checkIn.avgProtein ?? 0).rounded0) g protein a day.")
                    }
                    Text("Your targets were \(checkIn.previousCalories) Cal and \(checkIn.previousProtein) g protein.")
                    if let tdee = checkIn.tdeeEstimate { Text("Estimated maintenance: \(tdee.rounded0) Cal a day.") }
                }
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            } label: {
                Label(checkIn.compliant ? "You met your targets" : "Targets not met", systemImage: checkIn.compliant ? "star.fill" : "star")
            }
            .card()
        }
    }

    private var weightLabel: String {
        guard let c = checkIn.weightChange else { return "Not enough weigh-ins" }
        return c < 0 ? "Down \((-c).rounded1) lb this week" : "Up \(c.rounded1) lb this week"
    }
}
