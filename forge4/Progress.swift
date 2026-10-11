import SwiftUI
import Charts

struct ProgressPage: View {
    @EnvironmentObject private var data: FitStore
    @State private var chartChoice = 0
    @State private var editingWeight: WeightEntry?
    @State private var addingWeight = false

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: Date()) }
    }
    private var recentWeights: [WeightEntry] {
        data.weights.sorted { $0.date < $1.date }
    }
    private var weekAvgWeight: Double? {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        let points = data.weights.filter { $0.date >= cutoff }
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.kg } / Double(points.count)
    }
    private var weekVolume: Double {
        data.workouts.filter { $0.date >= Date().addingTimeInterval(-7 * 86400) }
            .flatMap(\.sets).reduce(0) { $0 + $1.volume }
    }
    private var records: [(String, LiftSet)] {
        let sets = data.workouts.flatMap(\.sets).filter { $0.working && $0.estimatedMax > 0 }
        let groups = Dictionary(grouping: sets, by: \.exercise)
        return groups.compactMap { (name, values) -> (String, LiftSet)? in
            guard let best = values.max(by: { $0.estimatedMax < $1.estimatedMax }) else { return nil }
            return (name, best)
        }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHead(title: "Progress", subtitle: "Trends from your actual logs.")
                    HStack(spacing: 10) {
                        metric("\(data.weekCount())", "Sessions / 7d")
                        metric("\(Int(weekVolume).formatted())", "Volume kg / 7d")
                        metric("\(data.weights.count)", "Weigh-ins")
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Body weight").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Button {
                                addingWeight = true
                            } label: {
                                Label("Log", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Forge.paleBlue)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(data.lastWeight?.short ?? "—")
                                .font(.system(size: 39, weight: .semibold, design: .rounded))
                            Text("kg").font(.subheadline).foregroundStyle(Forge.muted)
                            Spacer()
                            Text("Goal \(data.goals.targetKg.short) kg")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Forge.paleBlue)
                        }
                        if let avg = weekAvgWeight {
                            Text("7-day mean \(avg.short) kg")
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                        }
                        if recentWeights.count >= 2 {
                            Chart(recentWeights) { entry in
                                LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg))
                                    .interpolationMethod(.linear).foregroundStyle(Forge.blue)
                                PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg))
                                    .foregroundStyle(Forge.paleBlue)
                            }
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                            .frame(height: 184)
                        } else {
                            Text("Add at least two weigh-ins to view your trend.")
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }
                        if !data.weights.isEmpty {
                            ForEach(data.weights.sorted { $0.date > $1.date }.prefix(5)) { item in
                                HStack {
                                    Text(item.date.dayTitle)
                                        .font(.system(size: 12)).foregroundStyle(Forge.muted)
                                    Spacer()
                                    Text("\(item.kg.short) kg").font(.system(size: 13, weight: .semibold))
                                    Button {
                                        editingWeight = item
                                    } label: {
                                        Image(systemName: "pencil").foregroundStyle(Forge.paleBlue)
                                    }.buttonStyle(.plain)
                                    Button {
                                        data.weights.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(Forge.muted)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.surface()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Nutrition trend").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Picker("Metric", selection: $chartChoice) {
                                Text("Calories").tag(0)
                                Text("Protein").tag(1)
                            }.pickerStyle(.segmented).frame(width: 173)
                        }
                        Chart(days, id: \.self) { day in
                            BarMark(x: .value("Day", day, unit: .day),
                                    y: .value("Value", chartChoice == 0 ? data.kcal(on: day) : data.protein(on: day)))
                                .foregroundStyle(Forge.blue)
                                .cornerRadius(3)
                            RuleMark(y: .value("Goal", chartChoice == 0 ?
                                               Double(data.goals.calories) : Double(data.goals.protein)))
                                .foregroundStyle(Forge.paleBlue.opacity(0.65))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) {
                            _ in AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }}
                        .frame(height: 186)
                        Text(chartChoice == 0 ?
                             "Dashed line: daily calorie target" :
                             "Dashed line: daily protein target")
                            .font(.system(size: 11)).foregroundStyle(Forge.muted)
                    }.surface()

                    VStack(alignment: .leading, spacing: 13) {
                        Text("Working sets by muscle")
                            .font(.system(size: 17, weight: .semibold))
                        TinyLabel(text: "Last 7 days · warm-ups excluded")
                        ForEach(data.weeklyMuscleSets(), id: \.0) { muscle, count in
                            HStack {
                                Text(muscle).font(.system(size: 12)).frame(width: 80, alignment: .leading)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Forge.inset)
                                        Capsule().fill(Forge.blue)
                                            .frame(width: g.size.width * min(1, CGFloat(count) / 20))
                                    }
                                }.frame(height: 6)
                                Text("\(count)").font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit().frame(width: 24, alignment: .trailing)
                            }
                        }
                    }.surface()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personal records").font(.system(size: 17, weight: .semibold))
                        TinyLabel(text: "Highest estimated 1RM by exercise · sets of 1 to 12 reps")
                        if records.isEmpty {
                            Text("Finish workouts to populate your records.")
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                        }
                        ForEach(records, id: \.0) { exercise, record in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise).font(.system(size: 13, weight: .medium))
                                    Text("\(record.kg.short) kg × \(record.reps) reps")
                                        .font(.system(size: 11)).foregroundStyle(Forge.muted)
                                }
                                Spacer()
                                Text("\(record.estimatedMax.short) kg")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Forge.paleBlue)
                            }
                            if exercise != records.last?.0 {
                                Rectangle().fill(Forge.line).frame(height: 0.5)
                            }
                        }
                        Text("Estimated 1RM uses Epley. It is a training estimate, not a tested maximum.")
                            .font(.system(size: 10)).foregroundStyle(Forge.muted)
                    }.surface()
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }.forgePage()
            .sheet(isPresented: $addingWeight) {
                WeightEntryEditor(existing: nil).environmentObject(data)
            }
            .sheet(item: $editingWeight) { weight in
                WeightEntryEditor(existing: weight).environmentObject(data)
            }
        }
    }
    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 10)).foregroundStyle(Forge.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).surface(12)
    }
}
struct WeightEntryEditor: View {
    @EnvironmentObject private var data: FitStore
    @Environment(\.dismiss) private var dismiss
    let existing: WeightEntry?
    @State private var kilograms: String
    @State private var date: Date
    init(existing: WeightEntry?) {
        self.existing = existing
        _kilograms = State(initialValue: existing?.kg.short ?? "")
        _date = State(initialValue: existing?.date ?? Date())
    }
    private var amount: Double? { Double(kilograms.replacingOccurrences(of: ",", with: ".")) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                PageHead(title: "Weight", subtitle: "Weigh at a consistent time for better trends.")
                InsetField(label: "Body weight", value: $kilograms, suffix: "kg")
                HStack {
                    Text("Date").font(.subheadline)
                    Spacer()
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden().tint(Forge.paleBlue)
                }.surface()
                SolidAction(title: "Save weigh-in", symbol: "checkmark",
                            enabled: amount.map { $0 >= 25 && $0 <= 350 && $0.isFinite } ?? false) {
                    guard let value = amount, value >= 25, value <= 350 else { return }
                    let savedDate = Calendar.current.isDateInToday(date) ? Date() : date
                    var record = WeightEntry(kg: value, date: savedDate)
                    if let old = existing, let i = data.weights.firstIndex(where: { $0.id == old.id }) {
                        record.id = old.id
                        data.weights[i] = record
                    } else { data.weights.append(record) }
                    dismiss()
                }
                Spacer()
            }.padding(18).forgePage()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }.tint(Forge.paleBlue)
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}
