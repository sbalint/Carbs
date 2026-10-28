import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: Profile
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]

    private var latestWeight: Double { weights.last?.pounds ?? profile.startWeight }
    private var latestBodyFat: Double? { weights.last(where: { $0.bodyFatPct != nil })?.bodyFatPct }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Goal", selection: $profile.goalType) {
                        ForEach(GoalType.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Text("Start weight"); Spacer()
                        TextField("", value: $profile.startWeight, format: .number).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text("lb").foregroundStyle(Theme.secondaryText)
                    }
                    if profile.goalType != .maintain {
                        HStack {
                            Text("Goal weight"); Spacer()
                            TextField("", value: $profile.goalWeight, format: .number).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 90)
                            Text("lb").foregroundStyle(Theme.secondaryText)
                        }
                        RateEditor(rate: $profile.rateLbPerWeek, goal: profile.goalType, weight: latestWeight)
                    }
                }

                Section("Coaching") {
                    WeekdayPicker(weekday: $profile.checkInWeekday)
                    StylePicker(style: $profile.style)
                    FloorEditor(floor: $profile.calorieFloor)
                    if let tdee = profile.tdeeEstimate {
                        LabeledContent("Maintenance estimate", value: "\(tdee.rounded0) Cal")
                    }
                }

                Section {
                    Picker("Diet type", selection: Binding(get: { profile.dietType }, set: { profile.dietType = $0; replan() })) {
                        ForEach(DietType.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Protein")
                            Spacer()
                            Text("\(profile.proteinPerLbLBM.formatted(.number.precision(.fractionLength(2)))) g per lb lean mass")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Slider(value: $profile.proteinPerLbLBM, in: 0.7...1.5, step: 0.01) { _ in replan() }
                            .tint(Theme.protein)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Carbs \(Int((profile.carbShare * 100).rounded()))%")
                            Spacer()
                            Text("Fat \(100 - Int((profile.carbShare * 100).rounded()))%")
                        }
                        Slider(value: Binding(get: { profile.carbShare }, set: { profile.carbShare = $0; profile.dietTypeRaw = DietType.custom.rawValue }),
                               in: 0.05...0.8, step: 0.01) { _ in replan() }
                            .tint(Theme.carbs)
                    }
                } header: {
                    Text("Diet preferences")
                } footer: {
                    Text("Share of the calories left after protein. Lean mass uses your latest body fat (\(latestBodyFat.map { "\($0.rounded1)%" } ?? "assumed 25%")).")
                }

                Section {
                    Toggle("Set macros myself", isOn: $profile.useCustomMacros)
                    intRow("Calories", $profile.calories)
                    if profile.useCustomMacros {
                        intRow("Protein (g)", $profile.protein)
                        intRow("Carbs (g)", $profile.carbs)
                        intRow("Fat (g)", $profile.fat)
                    } else {
                        LabeledContent("Macros", value: "\(profile.protein)p · \(profile.carbs)c · \(profile.fat)f")
                    }
                } header: {
                    Text("Current targets")
                } footer: {
                    Text("Check-ins suggest new calories; you can always change them here.")
                }
                .onChange(of: profile.calories) { replan() }

                Section("Meals") {
                    ForEach(profile.mealNames.indices, id: \.self) { i in
                        TextField("Meal", text: $profile.mealNames[i])
                    }
                    if profile.mealNames.count < 7 {
                        Button("Add meal") { profile.mealNames.append("Meal \(profile.mealNames.count + 1)") }
                    }
                }

                Section {
                    TextField("DEMO_KEY", text: $profile.usdaAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("USDA API key")
                } footer: {
                    Text("Optional. The built-in demo key allows about 30 searches an hour. A free key from api.data.gov raises that to 1,000.")
                }

                Section("Loop") {
                    Text("Food entries keep their time and absorption, ready for Loop to offer as suggestions. The Loop connection comes in a later version; nothing is sent to Loop or Apple Health yet.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func replan() {
        profile.replanMacros(weightLb: latestWeight, bodyFatPct: latestBodyFat)
    }

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: .number).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}
