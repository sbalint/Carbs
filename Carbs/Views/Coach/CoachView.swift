import SwiftUI
import SwiftData

struct CoachView: View {
    @Bindable var profile: Profile
    @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]
    @Query private var allEntries: [FoodEntry]
    @State private var checkingIn = false
    @State private var addingWeight = false

    var body: some View {
        let period = Period.current(profile: profile, lastCheckIn: checkIns.first)
        let periodEntries = allEntries.filter { $0.timestamp >= period.start }
        let byDay = DayTotals.byDay(periodEntries)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GoalHeader(profile: profile, currentWeight: weights.last?.pounds) {
                        addingWeight = true
                    }
                    trackingCard(period: period, byDay: byDay)
                    targetsCard
                    complianceCard(period: period, byDay: byDay)
                    if !checkIns.isEmpty { historyCard }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Coach")
            .sheet(isPresented: $checkingIn) {
                CheckInFlowView(profile: profile, period: period, entries: periodEntries,
                                weights: weights, lastCheckIn: checkIns.first)
            }
            .sheet(isPresented: $addingWeight) { AddWeightView() }
        }
    }

    private func trackingCard(period: Period, byDay: [Date: DayTotals]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracking period").font(.headline)
                Spacer()
                Text("\(period.start.formatted(.dateTime.month(.abbreviated).day())) – \(period.checkInDate.adding(days: -1).formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            Text(period.isDue() ? "Today is your check-in day!" : "Your check-in is \(period.checkInDate.formatted(.dateTime.weekday(.wide).month().day())).")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            HStack {
                ForEach(period.days, id: \.self) { day in
                    let t = byDay[day]
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(Theme.primary.opacity(0.15), lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: min(1, (t?.calories ?? 0) / Double(max(1, profile.calories))))
                                .stroke(color(for: t), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 34, height: 34)
                        Text(day.formatted(.dateTime.day())).font(.caption2.weight(.semibold))
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button(period.isDue() ? "Check in" : "Check in early") { checkingIn = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .card()
    }

    private func color(for totals: DayTotals?) -> Color {
        guard let t = totals, t.count > 0 else { return Theme.secondaryText }
        let ratio = t.calories / Double(max(1, profile.calories))
        return CoachEngine.complianceRange(Double(profile.calories)).contains(t.calories.rounded()) ? Theme.good : ratio > 1 ? Theme.error : Theme.primary
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macro targets").font(.headline)
            Text(profile.useCustomMacros ? "Your custom targets." : "Your targets for this period.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            MacroStatBox(calories: Double(profile.calories), protein: Double(profile.protein),
                         carbs: Double(profile.carbs), fat: Double(profile.fat))
            HStack {
                Text("Diet: ").foregroundStyle(Theme.secondaryText) + Text(profile.dietType.title)
                Spacer()
                Text("Style: ").foregroundStyle(Theme.secondaryText) + Text(profile.style.title)
            }
            .font(.caption)
        }
        .card()
    }

    private func complianceCard(period: Period, byDay: [Date: DayTotals]) -> some View {
        let logged = byDay.filter { $0.key < Date.now.startOfDay }.values
        let n = Double(max(1, logged.count))
        let avgCal = logged.map(\.calories).reduce(0, +) / n
        let avgProtein = logged.map(\.protein).reduce(0, +) / n
        let calRange = CoachEngine.complianceRange(Double(profile.calories))
        let proteinMin = CoachEngine.complianceRange(Double(profile.protein)).lowerBound
        return VStack(alignment: .leading, spacing: 10) {
            Text("Compliance").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Target").foregroundStyle(Theme.secondaryText).gridColumnAlignment(.trailing)
                    Text("Avg so far").foregroundStyle(Theme.secondaryText).gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Cal")
                    Text("\(Int(calRange.lowerBound))–\(Int(calRange.upperBound))")
                    Text(logged.isEmpty ? "—" : avgCal.rounded0)
                }
                GridRow {
                    Text("Protein")
                    Text("≥ \(Int(proteinMin))g")
                    Text(logged.isEmpty ? "—" : "\(avgProtein.rounded0)g")
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            Text("Only calories and protein count toward hitting your targets. Today isn't included until the day is over.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Check-ins").font(.headline).padding(.bottom, 8)
            ForEach(checkIns) { c in
                NavigationLink {
                    ScrollView { CheckInReportView(checkIn: c).padding() }
                        .screenBackground()
                        .navigationTitle(c.date.formatted(.dateTime.month(.abbreviated).day()))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(c.periodStart.formatted(.dateTime.month(.abbreviated).day())) – \(c.date.adding(days: -1).formatted(.dateTime.month(.abbreviated).day()))")
                                if c.compliant { Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.primary) }
                            }
                            .foregroundStyle(Theme.text)
                            Text(summary(c)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 8)
                }
                Divider()
            }
        }
        .card()
    }

    private func summary(_ c: CheckIn) -> String {
        var parts: [String] = []
        if let w = c.weightChange { parts.append(String(format: "%+.1f lbs", w)) }
        if c.change != 0 { parts.append(String(format: "%+d Cal", c.change)) }
        if !c.followedSuggestion { parts.append("set manually") }
        return parts.isEmpty ? "No change" : parts.joined(separator: ", ")
    }
}

struct GoalHeader: View {
    let profile: Profile
    let currentWeight: Double?
    var onAddWeight: () -> Void

    var body: some View {
        let current = currentWeight ?? profile.startWeight
        let total = profile.startWeight - profile.goalWeight
        let progress = total != 0 ? (profile.startWeight - current) / total : 0
        VStack(spacing: 12) {
            Text(profile.goalType.title).font(.subheadline).foregroundStyle(Theme.secondaryText)
            if profile.goalType != .maintain {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%@%.2f", profile.goalType == .fatLoss ? "-" : "+", profile.rateLbPerWeek))
                        .font(.heading(34))
                    Text("lb/week").foregroundStyle(Theme.secondaryText)
                }
            }
            ProgressView(value: min(1, max(0, progress))).tint(Theme.primary)
            HStack {
                stat(profile.startWeight, "Start")
                Spacer()
                stat(current, "Current")
                Spacer()
                stat(profile.goalWeight, "Goal")
            }
            Button(action: onAddWeight) { Label("Add weight", systemImage: "plus.circle") }
                .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func stat(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value.rounded1) lb").font(.subheadline.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}
