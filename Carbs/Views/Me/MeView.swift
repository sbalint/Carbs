import SwiftUI
import SwiftData
import Charts

struct MeView: View {
    @Environment(\.modelContext) private var context
    let profile: Profile
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]
    @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
    @Query private var entries: [FoodEntry]
    @State private var range = 30
    @State private var addingWeight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $range) {
                        Text("Week").tag(7)
                        Text("Month").tag(30)
                        Text("3 Months").tag(90)
                        Text("Year").tag(365)
                    }
                    .pickerStyle(.segmented)
                    weightCard
                    if weights.contains(where: { $0.bodyFatPct != nil }) {
                        measurementCard("Body fat", unit: "%", color: Theme.fat, values: weights.compactMap { w in w.bodyFatPct.map { (w.date, $0) } })
                    }
                    if weights.contains(where: { $0.waistInches != nil }) {
                        measurementCard("Waist", unit: "in", color: Theme.carbs, values: weights.compactMap { w in w.waistInches.map { (w.date, $0) } })
                    }
                    caloriesCard
                    if checkIns.contains(where: { $0.tdeeEstimate != nil }) { maintenanceCard }
                    weighInList
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Me")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingWeight = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $addingWeight) { AddWeightView() }
        }
    }

    private var start: Date { Date.now.startOfDay.adding(days: -range + 1) }

    private var weightCard: some View {
        let points = weights.map { WeightPoint(date: $0.date, pounds: $0.pounds) }
        let trend = TrendWeight.series(points, through: .now).filter { $0.date >= start }
        let shown = weights.filter { $0.date >= start }
        let values = shown.map(\.pounds) + trend.map(\.trend)
        let low = (values.min() ?? 0) - 2, high = (values.max() ?? 0) + 2
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weight").font(.headline)
                Spacer()
                if let t = trend.last { Text("Trend \(t.trend.rounded1) lb").font(.subheadline).foregroundStyle(Theme.secondaryText) }
            }
            if shown.isEmpty {
                Text("No weigh-ins in this range.").foregroundStyle(Theme.secondaryText)
            } else {
                Chart {
                    ForEach(shown) { w in
                        PointMark(x: .value("Date", w.date), y: .value("Weight", w.pounds))
                            .foregroundStyle(Theme.secondaryText.opacity(0.6))
                            .symbolSize(20)
                    }
                    ForEach(trend, id: \.date) { t in
                        LineMark(x: .value("Date", t.date), y: .value("Trend", t.trend))
                            .foregroundStyle(Theme.primary)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: low...high)
                .frame(height: 200)
                Text("Dots are weigh-ins; the line is your smoothed trend weight.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func measurementCard(_ title: String, unit: String, color: Color, values: [(date: Date, value: Double)]) -> some View {
        let shown = values.filter { $0.date >= start }
        let low = (shown.map(\.value).min() ?? 0) - 1, high = (shown.map(\.value).max() ?? 0) + 1
        let space = unit == "%" ? "" : " "
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let last = values.last {
                    Text(last.value.rounded1 + space + unit).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            if shown.isEmpty {
                Text("None in this range.").foregroundStyle(Theme.secondaryText)
            } else {
                Chart(shown, id: \.date) { p in
                    LineMark(x: .value("Date", p.date), y: .value(title, p.value))
                        .foregroundStyle(color)
                    PointMark(x: .value("Date", p.date), y: .value(title, p.value))
                        .foregroundStyle(color)
                        .symbolSize(24)
                }
                .chartYScale(domain: low...high)
                .frame(height: 140)
                if let first = shown.first, let last = shown.last, shown.count > 1 {
                    Text(String(format: "%+.1f%@%@ since %@", last.value - first.value, space, unit,
                                first.date.formatted(.dateTime.month(.abbreviated).day())))
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .card()
    }

    private var caloriesCard: some View {
        let byDay = DayTotals.byDay(entries.filter { $0.timestamp >= start })
        let days = byDay.sorted { $0.key < $1.key }
        let avg = days.isEmpty ? 0 : days.map(\.value.calories).reduce(0, +) / Double(days.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calories").font(.headline)
                Spacer()
                Text("Avg \(avg.rounded0) Cal").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            Chart {
                ForEach(days, id: \.key) { day in
                    BarMark(x: .value("Day", day.key, unit: .day), y: .value("Calories", day.value.calories))
                        .foregroundStyle(Theme.primary)
                }
                RuleMark(y: .value("Target", profile.calories))
                    .foregroundStyle(Theme.carbs)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .frame(height: 160)
        }
        .card()
    }

    private var maintenanceCard: some View {
        let points = checkIns.filter { $0.tdeeEstimate != nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Maintenance estimate").font(.headline)
                Spacer()
                if let last = points.last?.tdeeEstimate { Text("\(last.rounded0) Cal").foregroundStyle(Theme.secondaryText) }
            }
            Chart(points) { c in
                LineMark(x: .value("Date", c.date), y: .value("Maintenance", c.tdeeEstimate ?? 0))
                    .foregroundStyle(Theme.fat)
                PointMark(x: .value("Date", c.date), y: .value("Maintenance", c.tdeeEstimate ?? 0))
                    .foregroundStyle(Theme.fat)
            }
            .frame(height: 140)
        }
        .card()
    }

    private var weighInList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weigh-ins").font(.headline).padding(.bottom, 8)
            ForEach(weights.reversed().prefix(30)) { w in
                HStack {
                    Text(w.date.formatted(date: .abbreviated, time: .omitted))
                    if w.fromHealth {
                        Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
                            .accessibilityLabel("From Apple Health")
                    }
                    Spacer()
                    if let waist = w.waistInches { Text("\(waist.rounded1) in").foregroundStyle(Theme.secondaryText) }
                    if let bf = w.bodyFatPct { Text("\(bf.rounded1)%").foregroundStyle(Theme.secondaryText) }
                    Text("\(w.pounds.rounded1) lb").monospacedDigit()
                }
                .padding(.vertical, 8)
                .contextMenu {
                    Button("Delete", role: .destructive) { context.delete(w) }
                }
                Divider()
            }
        }
        .card()
    }
}

struct AddWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date.now
    @State private var pounds: Double?
    @State private var bodyFat: Double?
    @State private var waist: Double?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                numberField("Weight (lb)", $pounds)
                numberField("Body fat % (optional)", $bodyFat)
                numberField("Waist in (optional)", $waist)
            }
            .keyboardDoneButton()
            .navigationTitle("Add weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let pounds {
                            context.insert(WeightLog(date: date, pounds: pounds, bodyFatPct: bodyFat, waistInches: waist))
                            try? context.save()
                        }
                        dismiss()
                    }
                    .disabled(pounds == nil)
                }
            }
        }
    }
}
