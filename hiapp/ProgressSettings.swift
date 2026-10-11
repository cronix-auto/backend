import SwiftUI
import Charts

struct ProgressScreenView: View {
    @EnvironmentObject var fit: FitStore
    @State private var showingWeight = false
    @State private var chartMode = 0

    private var recentDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: Date()) }
    }
    private var weekSessions: Int {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return fit.workouts.filter { $0.date >= start }.count
    }
    private var volume: Int {
        Int(fit.workouts.flatMap { $0.sets }.reduce(0.0) { $0 + $1.kg * Double($1.reps) })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Headline(label: "Your progress", detail: "The bigger picture")
                        Spacer()
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 30)).foregroundStyle(FitStyle.pale)
                    }.padding(.top, 10)

                    HStack(spacing: 12) {
                        summary("Sessions", value: "\(weekSessions)", detail: "Last 7 days", icon: "dumbbell.fill")
                        summary("Volume", value: "\(volume.formatted())", detail: "Total kg lifted", icon: "bolt.fill")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SmallLabel(text: "Weight trend")
                            Spacer()
                            Button { showingWeight = true } label: {
                                Label("Log weight", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(FitStyle.pale)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(fit.lastWeight.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(size: 43, weight: .bold, design: .rounded))
                            Text("kg").font(.subheadline).foregroundStyle(FitStyle.muted)
                            Spacer()
                            Text("Target \(Int(fit.goals.targetKg)) kg")
                                .font(.caption.weight(.semibold)).foregroundStyle(FitStyle.pale)
                        }
                        if fit.weights.count >= 2 {
                            Chart(fit.weights.sorted { $0.date < $1.date }) { entry in
                                LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg))
                                    .interpolationMethod(.catmullRom).foregroundStyle(FitStyle.mint)
                                PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg))
                                    .foregroundStyle(FitStyle.pale)
                            }.frame(height: 160)
                        } else {
                            Text("Log your weight a few times to see a trend.")
                                .font(.subheadline).foregroundStyle(FitStyle.muted)
                                .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                        }
                    }.fitCard()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SmallLabel(text: "Last 7 days")
                            Spacer()
                            Picker("Metric", selection: $chartMode) {
                                Text("Calories").tag(0)
                                Text("Protein").tag(1)
                            }.pickerStyle(.segmented).frame(width: 186)
                        }
                        Chart(recentDays, id: \.self) { date in
                            BarMark(
                                x: .value("Day", date, unit: .day),
                                y: .value("Amount", chartMode == 0 ? fit.kcal(on: date) : fit.protein(on: date))
                            ).foregroundStyle(FitStyle.blue.gradient).cornerRadius(5)
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 190)
                        Text(chartMode == 0 ? "Food calories logged per day" : "Protein grams logged per day")
                            .font(.caption).foregroundStyle(FitStyle.muted)
                    }.fitCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SmallLabel(text: "Latest sessions")
                        if fit.workouts.isEmpty {
                            Text("Your training history appears here after you finish a workout.")
                                .font(.subheadline).foregroundStyle(FitStyle.muted)
                        }
                        ForEach(fit.workouts.prefix(8)) { workout in
                            HStack {
                                Image(systemName: "dumbbell.fill").foregroundStyle(FitStyle.pale)
                                VStack(alignment: .leading) {
                                    Text(workout.name).font(.subheadline.weight(.semibold))
                                    Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                Text("\(workout.sets.count) sets").font(.caption).foregroundStyle(FitStyle.muted)
                            }
                            if workout.id != fit.workouts.prefix(8).last?.id {
                                Divider().overlay(.white.opacity(0.08))
                            }
                        }
                    }.fitCard()
                }
                .padding(18)
            }
            .background(DeepBlueBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingWeight) { WeightLogSheet() }
        }
    }

    private func summary(_ label: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(FitStyle.pale).font(.title3)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(FitStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
    }
}

struct WeightLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var fit: FitStore
    @State private var weightText = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Log your weight").font(.title2.bold())
                Text("Use the same scale and similar time of day for reliable trends.")
                    .font(.subheadline).foregroundStyle(FitStyle.muted)
                TextField("Weight in kg", text: $weightText)
                    .keyboardType(.decimalPad).padding(16).liquidField()
                Button("Save weight") {
                    guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 25, value < 350 else { return }
                    fit.weights.append(WeightEntry(kg: value))
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(FitStyle.blue)
                .frame(maxWidth: .infinity)
                Spacer()
            }.padding(22).background(DeepBlueBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct SettingsView: View {
    @EnvironmentObject var fit: FitStore
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fats = ""
    @State private var water = ""
    @State private var target = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Headline(label: "Your goals", detail: "Make the plan yours")
                        Spacer()
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 30)).foregroundStyle(FitStyle.pale)
                    }.padding(.top, 10)
                    VStack(alignment: .leading, spacing: 16) {
                        SmallLabel(text: "Daily nutrition")
                        goalField("Calorie target", value: $calories, suffix: "kcal", icon: "flame")
                        goalField("Protein", value: $protein, suffix: "g", icon: "p.circle")
                        goalField("Carbs", value: $carbs, suffix: "g", icon: "circle.hexagongrid")
                        goalField("Fat", value: $fats, suffix: "g", icon: "drop")
                    }.fitCard()
                    VStack(alignment: .leading, spacing: 16) {
                        SmallLabel(text: "Hydration & bodyweight")
                        goalField("Water", value: $water, suffix: "ml", icon: "drop.fill")
                        goalField("Target weight", value: $target, suffix: "kg", icon: "scalemass")
                    }.fitCard()
                    Button {
                        var g = fit.goals
                        if let v = Int(calories), (1000...6000).contains(v) { g.calories = v }
                        if let v = Int(protein), (0...400).contains(v) { g.protein = v }
                        if let v = Int(carbs), (0...800).contains(v) { g.carbs = v }
                        if let v = Int(fats), (0...300).contains(v) { g.fat = v }
                        if let v = Int(water), (250...8000).contains(v) { g.water = v }
                        if let v = Double(target.replacingOccurrences(of: ",", with: ".")), (35...350).contains(v) { g.targetKg = v }
                        fit.goals = g
                        saved = true
                    } label: {
                        Label(saved ? "Goals saved" : "Save goals", systemImage: saved ? "checkmark.circle.fill" : "checkmark")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(.borderedProminent).tint(FitStyle.blue)
                    VStack(alignment: .leading, spacing: 10) {
                        SmallLabel(text: "Your privacy")
                        Label("Your meals, sets and weight logs stay on your iPhone.", systemImage: "iphone")
                        Label("No Apple Health access or health permissions.", systemImage: "hand.raised")
                        Label("Nothing is automatically sent to a server.", systemImage: "lock.shield")
                    }.font(.caption).foregroundStyle(FitStyle.muted).fitCard()
                    Text("Food presets are estimates. Verify labels and adjust portions for accurate tracking.")
                        .font(.caption2).foregroundStyle(FitStyle.muted)
                        .padding(.horizontal, 4)
                }.padding(18)
            }
            .background(DeepBlueBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: load)
        }
    }

    private func load() {
        calories = String(fit.goals.calories)
        protein = String(fit.goals.protein)
        carbs = String(fit.goals.carbs)
        fats = String(fit.goals.fat)
        water = String(fit.goals.water)
        target = fit.goals.targetKg.formatted()
        saved = false
    }

    private func goalField(_ label: String, value: Binding<String>, suffix: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 23).foregroundStyle(FitStyle.pale)
            Text(label).font(.subheadline)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.bold))
                .frame(width: 82)
            Text(suffix).font(.caption2).foregroundStyle(FitStyle.muted)
                .frame(width: 33, alignment: .leading)
        }.padding(.vertical, 4)
    }
}
