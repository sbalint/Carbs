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

    private var canSave: Bool { weight != nil && calories != nil && (goal == .maintain || goalWeight != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set up your goal. You can change any of this later in Settings.")
                        .foregroundStyle(Theme.secondaryText)
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
                    intRow("Daily calories now", value: $calories)
                    intRow("Maintenance (optional)", value: $maintenance)
                } header: {
                    Text("Starting calories")
                } footer: {
                    Text("Use your current calorie target and maintenance estimate from another app if you have them. Carbs refines the estimate from your logs every week.")
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

    private func save() {
        guard let weight, let calories else { return }
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
        profile.tdeeEstimate = maintenance.map(Double.init)
            ?? Double(calories) + (goal == .fatLoss ? rate * 500 : goal == .gain ? -rate * 500 : 0)
        profile.replanMacros(weightLb: weight, bodyFatPct: bodyFat)
        context.insert(profile)
        context.insert(WeightLog(date: .now, pounds: weight, bodyFatPct: bodyFat))
        try? context.save()
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

    private func intRow(_ title: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("Cal").foregroundStyle(Theme.secondaryText)
        }
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
