import SwiftUI
import Charts

struct ProgressScreen: View {
    @EnvironmentObject var data: FitnessStore
    @EnvironmentObject var health: HealthBridge
    @State private var metric = 0
    @State private var showingWeight = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                FitHeader(title: "See the work pay off.", subtitle: "Progress is consistency, not a perfect day.")
                HStack(spacing: 10) {
                    MetricTile(icon: "calendar", value: "\(data.workoutsThisWeek())", title: "Workouts / 7 days", tint: FitStyle.lime)
                    MetricTile(icon: "scalemass.fill", value: currentWeight, title: "Latest weight", tint: FitStyle.orange)
                }
                FitCard {
                    HStack {
                        Text("LAST 7 DAYS").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(FitStyle.muted)
                        Spacer()
                    }
                    Picker("Metric", selection: $metric) {
                        Text("Calories").tag(0)
                        Text("Protein").tag(1)
                    }.pickerStyle(.segmented).padding(.vertical, 9)
                    Chart(data.lastSevenDays(), id: \.self) { day in
                        BarMark(
                            x: .value("Date", day, unit: .day),
                            y: .value("Value", metric == 0 ? data.caloriesOn(day) : data.proteinOn(day))
                        )
                        .foregroundStyle(metric == 0 ? FitStyle.orange : FitStyle.lime)
                        .cornerRadius(5)
                    }
                    .chartYScale(domain: 0...max(1.0, metric == 0 ? Double(data.calorieGoal) * 1.3 : Double(data.proteinGoal) * 1.4))
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 190)
                    HStack {
                        Text("Daily goal").font(.caption).foregroundStyle(FitStyle.muted)
                        Spacer()
                        Text(metric == 0 ? "\(data.calorieGoal) kcal" : "\(data.proteinGoal) g")
                            .font(.caption.weight(.semibold))
                    }
                }
                FitCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("BODY WEIGHT").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(FitStyle.muted)
                            Text("Target: \(data.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg")
                                .font(.headline).foregroundStyle(FitStyle.lime)
                        }
                        Spacer()
                        Button { showingWeight = true } label: {
                            Image(systemName: "plus").font(.headline)
                                .frame(width: 40, height: 40)
                                .background(FitStyle.card2, in: Circle())
                        }
                    }
                    if data.weights.count >= 2 {
                        Chart(data.weights.sorted { $0.date < $1.date }) { weight in
                            LineMark(x: .value("Date", weight.date), y: .value("Kg", weight.kg))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(FitStyle.lime)
                            PointMark(x: .value("Date", weight.date), y: .value("Kg", weight.kg))
                                .foregroundStyle(FitStyle.lime)
                        }.frame(height: 165).padding(.top, 9)
                    } else {
                        Text("Add weight readings over time to see your trend.")
                            .font(.subheadline).foregroundStyle(FitStyle.muted).padding(.top, 10)
                    }
                    if let healthWeight = health.bodyMass {
                        Text("Apple Health latest: \(healthWeight.formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.caption).foregroundStyle(FitStyle.muted).padding(.top, 5)
                    }
                }
                FitCard {
                    Text("MOMENTUM").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(FitStyle.muted)
                    VStack(spacing: 12) {
                        progressLine("Protein today", value: data.proteinOn(), goal: Double(data.proteinGoal), units: "g", tint: FitStyle.lime)
                        progressLine("Water today", value: Double(data.waterToday()), goal: Double(data.waterGoal), units: "ml", tint: .cyan)
                        progressLine("Food logged", value: Double(data.foodsOn().count), goal: 3, units: "meals", tint: FitStyle.orange)
                    }.padding(.top, 6)
                }
            }.padding(.horizontal, 19).padding(.top, 17).padding(.bottom, 30)
        }
        .background(FitStyle.bg.ignoresSafeArea())
        .sheet(isPresented: $showingWeight) { WeightSheet() }
    }

    private var currentWeight: String {
        if let weight = data.weights.sorted(by: { $0.date > $1.date }).first { return String(format: "%.1f kg", weight.kg) }
        if let weight = health.bodyMass { return String(format: "%.1f kg", weight) }
        return "—"
    }

    private func progressLine(_ title: String, value: Double, goal: Double, units: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(value))/\(Int(goal)) \(units)").font(.caption).foregroundStyle(FitStyle.muted)
            }
            ProgressView(value: min(1, value / max(1, goal))).tint(tint)
        }
    }
}

struct WeightSheet: View {
    @EnvironmentObject var data: FitnessStore
    @Environment(\.dismiss) var dismiss
    @State private var kg = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Weight in kilograms") {
                    TextField("e.g. 105.5", text: $kg).keyboardType(.decimalPad)
                }
                Section {
                    Button("Save reading") {
                        guard let value = Double(kg.replacingOccurrences(of: ",", with: ".")), value > 20, value < 500 else { return }
                        data.weights.insert(WeightRecord(kg: value), at: 0)
                        dismiss()
                    }.fontWeight(.bold).foregroundStyle(FitStyle.lime)
                }
                Section {
                    Text("Manual weigh-ins are saved locally. Apple Health weight is displayed separately when connected.")
                        .font(.caption).foregroundStyle(FitStyle.muted)
                }
            }
            .scrollContentBackground(.hidden).background(FitStyle.bg)
            .navigationTitle("Log weight")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct ProfileScreen: View {
    @EnvironmentObject var data: FitnessStore
    @EnvironmentObject var health: HealthBridge
    @AppStorage("fit.syncFoodToHealth") private var syncFood = false
    @AppStorage("fit.syncWorkoutsToHealth") private var syncWorkouts = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FitHeader(title: "Make it yours.", subtitle: "Your targets, your health, your privacy.")
                    FitCard {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                                .font(.largeTitle).foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("APPLE HEALTH").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(FitStyle.muted)
                                Text(health.status).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button {
                            health.connect()
                        } label: {
                            HStack {
                                Image(systemName: "heart.circle")
                                Text(health.busy ? "Requesting access…" : "Connect / Manage access")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FitStyle.bg)
                            .padding(14)
                            .background(FitStyle.lime, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .disabled(health.busy || !health.isAvailable)
                        .padding(.top, 10)
                        Toggle("Send new food logs to Health", isOn: $syncFood).tint(FitStyle.lime)
                            .font(.subheadline).padding(.top, 6)
                        Toggle("Send finished workouts to Health", isOn: $syncWorkouts).tint(FitStyle.lime)
                            .font(.subheadline)
                        Text("Apple Health data is read only with your permission. Sync requires HealthKit signing entitlement. Removing an entry here will not remove its previously synced Health record.")
                            .font(.caption2).foregroundStyle(FitStyle.muted)
                    }
                    Text("YOUR GOALS").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted)
                    FitCard {
                        VStack(spacing: 15) {
                            Stepper(value: $data.calorieGoal, in: 1200...4500, step: 100) {
                                goalRow("Daily calories", "\(data.calorieGoal) kcal", icon: "flame.fill", tint: FitStyle.orange)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            Stepper(value: $data.proteinGoal, in: 60...250, step: 10) {
                                goalRow("Daily protein", "\(data.proteinGoal) g", icon: "bolt.fill", tint: FitStyle.lime)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            Stepper(value: $data.waterGoal, in: 1000...5000, step: 250) {
                                goalRow("Daily water", "\(data.waterGoal) ml", icon: "drop.fill", tint: .cyan)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            Stepper(value: $data.targetWeight, in: 50...200, step: 1) {
                                goalRow("Weight goal", "\(Int(data.targetWeight)) kg", icon: "scalemass", tint: .purple)
                            }
                        }
                    }
                    FitCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("BUILT FOR YOUR ROUTINE").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(FitStyle.muted)
                            Label("High-protein meals with customizable portions", systemImage: "fork.knife")
                            Label("Push, pull, legs, arms and incline-cardio sessions", systemImage: "dumbbell.fill")
                            Label("Focus on strength progress and consistency", systemImage: "chart.line.uptrend.xyaxis")
                        }.font(.subheadline)
                    }
                    Text("Data is kept in local app storage. Deleting the app can erase your logs. This build has no cloud account, food scanner or HealthKit background sync.")
                        .font(.caption2).foregroundStyle(FitStyle.muted).padding(.bottom, 28)
                }.padding(.horizontal, 19).padding(.top, 17)
            }
            .background(FitStyle.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func goalRow(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 23)
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        }
    }
}
