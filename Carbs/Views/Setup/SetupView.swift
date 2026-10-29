import SwiftUI
import SwiftData

/// First launch: goal, starting numbers and coaching style.
struct SetupView: View {
    @Environment(\.modelContext) private var context

    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var goalWeight: Double?
    @State private var goal: GoalType = .fatLoss
    @State private var rate: Double = 2.0
    @State private var calories: Int?
    @State private var maintenance: Int?
    @State private var checkInWeekday = 4
    @State private var style: AdjustmentStyle = .aggressive
    @State private var floor: Double = 1500
    @State private var sex: Sex?
    @State private var age: Int?
    @State private var heightFeet: Int?
    @State private var heightInches: Int?
    @State private var activity: ActivityLevel = .light
    @State private var healthImport = false

    private var heightIn: Double? {
        guard let heightFeet else { return nil }
        return Double(heightFeet * 12 + (heightInches ?? 0))
    }
    /// Maintenance from body stats, once they're filled in.
    private var estimatedMaintenance: Int? {
        guard let weight, let heightIn, let age, let sex else { return nil }
        return Maintenance.estimate(weightLb: weight, heightIn: heightIn, age: age, sex: sex, activity: activity, bodyFatPct: bodyFat)
    }
    private var effectiveMaintenance: Int? { maintenance ?? estimatedMaintenance }
    private var suggestedCalories: Int? {
        effectiveMaintenance.map { Maintenance.goalCalories(maintenance: Double($0), goal: goal, rateLbPerWeek: rate, floor: floor) }
    }
    private var effectiveCalories: Int? { calories ?? suggestedCalories }

    private var canSave: Bool { weight != nil && effectiveCalories != nil && (goal == .maintain || goalWeight != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set up your goal. You can change any of this later in Settings.")
                        .foregroundStyle(Theme.secondaryText)
                }
                if HealthService.shared.isAvailable {
                    Section {
                        Button { Task { await fillFromHealth() } } label: {
                            Label(healthImport ? "Filled in from Apple Health" : "Fill in from Apple Health",
                                  systemImage: healthImport ? "checkmark.circle.fill" : "heart.text.square")
                        }
                    } footer: {
                        Text("Uses your latest weight, body fat, height, sex and age from Health, and keeps importing weigh-ins.")
                    }
                }
                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(GoalType.allCases) { Text($0.title).tag($0) }
                    }
                    numberRow("Current weight", value: $weight, unit: "lb")
                    numberRow("Body fat (optional)", value: $bodyFat, unit: "%")
                    if goal != .maintain {
                        numberRow("Goal weight", value: $goalWeight, unit: "lb")
                        RateEditor(rate: $rate, goal: goal, weight: weight)
                    }
                }
                Section {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.title).tag(Sex?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    intRow("Age", value: $age, unit: "yr")
                    HStack {
                        Text("Height")
                        Spacer()
                        smallField(value: $heightFeet)
                        Text("ft").foregroundStyle(Theme.secondaryText)
                        smallField(value: $heightInches)
                        Text("in").foregroundStyle(Theme.secondaryText)
                    }
                    ActivityPicker(activity: $activity)
                } header: {
                    Text("About you")
                } footer: {
                    Text("Used to estimate your maintenance calories.")
                }
                Section {
                    intRow("Maintenance", value: $maintenance, placeholder: estimatedMaintenance)
                    intRow("Daily calories", value: $calories, placeholder: suggestedCalories)
                } header: {
                    Text("Starting calories")
                } footer: {
                    Text(caloriesFooter)
                }
                Section {
                    WeekdayPicker(weekday: $checkInWeekday)
                    StylePicker(style: $style)
                    FloorEditor(floor: $floor)
                } header: {
                    Text("Coaching")
                }
                Section {
                    Button("Start") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSave)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Welcome to Carbs")
        }
    }

    private var caloriesFooter: String {
        guard let maintenance = effectiveMaintenance else {
            return "Fill in About you for an estimate, or type your own numbers."
        }
        var text = self.maintenance == nil
            ? "Estimated maintenance is \(maintenance.formatted()) Cal for your size, age and activity. "
            : ""
        switch goal {
        case .fatLoss:
            text += "Losing \(rate.rounded1) lb a week takes about \(Int(rate * 500).formatted()) Cal a day off maintenance"
            text += Double(maintenance) - rate * 500 < floor ? ", held at your \(Int(floor)) Cal floor. " : ". "
        case .gain:
            text += "Gaining \(rate.rounded1) lb a week adds about \(Int(rate * 500).formatted()) Cal a day. "
        case .maintain:
            break
        }
        text += "Type over the grey numbers to use your own. "
        return text + "Carbs refines maintenance from your logs at each check-in."
    }

    private func save() {
        guard let weight, let calories = effectiveCalories else { return }
        let profile = Profile()
        profile.goalType = goal
        profile.goalStartDate = .now
        profile.startWeight = weight
        profile.goalWeight = goal == .maintain ? weight : (goalWeight ?? weight)
        profile.rateLbPerWeek = goal == .maintain ? 0 : rate
        profile.checkInWeekday = checkInWeekday
        profile.style = style
        profile.calorieFloor = floor
        profile.calories = calories
        profile.sex = sex
        profile.age = age
        profile.heightInches = heightIn ?? 0
        profile.activity = activity
        profile.healthImport = healthImport
        profile.tdeeEstimate = effectiveMaintenance.map(Double.init)
            ?? Double(calories) + (goal == .fatLoss ? rate * 500 : goal == .gain ? -rate * 500 : 0)
        profile.replanMacros(weightLb: weight, bodyFatPct: bodyFat)
        context.insert(profile)
        context.insert(WeightLog(date: .now, pounds: weight, bodyFatPct: bodyFat))
        try? context.save()
    }

    private func fillFromHealth() async {
        await HealthService.shared.requestAccess()
        let stats = await HealthService.shared.stats()
        weight = weight ?? stats.pounds.map { ($0 * 10).rounded() / 10 }
        bodyFat = bodyFat ?? stats.bodyFatPct.map { ($0 * 10).rounded() / 10 }
        sex = sex ?? stats.sex
        if age == nil, let year = stats.birthYear { age = Calendar.current.component(.year, from: .now) - year }
        if heightFeet == nil, let height = stats.heightInches {
            let total = Int(height.rounded())
            heightFeet = total / 12
            heightInches = total % 12
        }
        healthImport = true
    }

    private func numberRow(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(Theme.secondaryText)
        }
    }

    private func intRow(_ title: String, value: Binding<Int?>, placeholder: Int? = nil, unit: String = "Cal") -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder.map { "\($0)" } ?? "—", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(Theme.secondaryText)
        }
    }

    private func smallField(value: Binding<Int?>) -> some View {
        TextField("—", value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 36)
    }
}

// MARK: - Shared coaching controls (also used in Settings)

struct RateEditor: View {
    @Binding var rate: Double
    var goal: GoalType
    var weight: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal == .gain ? "Gain rate" : "Loss rate")
                Spacer()
                Text("\(rate.rounded1) lb/week").monospacedDigit().foregroundStyle(Theme.primary)
            }
            Slider(value: $rate, in: goal == .gain ? 0.25...1.5 : 0.5...3.0, step: 0.1)
            if let weight, weight > 0 {
                let percent = rate / weight * 100
                Text(String(format: "%.1f%% of body weight per week. ", percent)
                     + (goal == .fatLoss
                        ? "A common guideline is 0.5–1% (\((weight * 0.005).rounded1)–\((weight * 0.01).rounded1) lb)."
                        : ""))
                    .font(.caption)
                    .foregroundStyle(goal == .fatLoss && percent > 1 ? Theme.carbs : Theme.secondaryText)
            }
        }
    }
}

struct ActivityPicker: View {
    @Binding var activity: ActivityLevel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Activity", selection: $activity) {
                ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
            }
            Text(activity.detail).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct WeekdayPicker: View {
    @Binding var weekday: Int
    var body: some View {
        Picker("Check-in day", selection: $weekday) {
            ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
        }
    }
}

struct StylePicker: View {
    @Binding var style: AdjustmentStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Adjustment style", selection: $style) {
                ForEach(AdjustmentStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(style.detail).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct FloorEditor: View {
    @Binding var floor: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $floor, in: 1000...3000, step: 50) {
                HStack {
                    Text("Calorie floor")
                    Spacer()
                    Text("\(Int(floor)) Cal").monospacedDigit().foregroundStyle(Theme.primary)
                }
            }
            Text("Suggestions never go below this.").font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}
