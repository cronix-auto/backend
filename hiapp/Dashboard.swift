import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var fit: FitStore
    @EnvironmentObject var health: AppleHealth
    @Binding var selectedTab: Int
    private var today: Date { Date() }
    private var calories: Double { fit.kcal(on: today) }
    private var protein: Double { fit.protein(on: today) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    hero
                    HStack(spacing: 12) {
                        macroTile("PROTEIN", amount: protein, goal: Double(fit.goals.protein), color: FitStyle.mint, unit: "g")
                        macroTile("CARBS", amount: fit.carbs(on: today), goal: Double(fit.goals.carbs), color: FitStyle.blue, unit: "g")
                        macroTile("FATS", amount: fit.fat(on: today), goal: Double(fit.goals.fat), color: FitStyle.orange, unit: "g")
                    }
                    HStack {
                        Text("APPLE HEALTH").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.4)
                        Spacer()
                        Button { if health.hasRequested { health.refresh() } else { health.connect() } } label: {
                            Label(health.hasRequested ? "Refresh" : "Connect", systemImage: "heart.text.square")
                                .font(.system(size: 12, weight: .semibold))
                        }.tint(FitStyle.mint)
                    }.padding(.top, 6)
                    HStack(spacing: 12) {
                        healthTile("Steps", icon: "figure.walk", value: health.hasRequested ? health.steps.formatted() : "—", detail: "\(fit.goals.steps.formatted()) target", color: FitStyle.mint)
                        healthTile("Active kcal", icon: "flame.fill", value: health.hasRequested ? health.activeCalories.formatted() : "—", detail: "From Apple Health", color: FitStyle.orange)
                    }
                    HStack(spacing: 12) {
                        healthTile("Distance", icon: "point.topleft.down.curvedto.point.bottomright.up", value: health.hasRequested ? String(format: "%.1f km", health.distanceKm) : "—", detail: "Walking + running", color: FitStyle.blue)
                        healthTile("Weight", icon: "scalemass.fill", value: ((fit.lastWeight ?? health.latestWeightKg).map { String(format: "%.1f kg", $0) } ?? "—"), detail: "Latest entry", color: FitStyle.mint)
                    }
                    waterCard
                    trainingCard
                    weekChart
                    Text("Apple Health activity is shown separately. Exercise calories are not subtracted from your food target.")
                        .font(.caption2).foregroundStyle(FitStyle.muted).padding(.bottom, 10)
                }
                .padding(18)
            }
            .background(FitStyle.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FORGE").font(.system(size: 13, weight: .black, design: .rounded)).tracking(4).foregroundStyle(FitStyle.orange)
                Text("Your daily edge.").font(.system(size: 29, weight: .bold, design: .rounded))
                Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.subheadline).foregroundStyle(FitStyle.muted)
            }
            Spacer()
            Image(systemName: "bolt.heart.fill")
                .font(.title2).foregroundStyle(FitStyle.orange)
                .padding(13).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 15))
        }.padding(.top, 10)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SmallLabel(text: "Daily fuel")
                Spacer()
                Label("FOOD", systemImage: "fork.knife").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.65))
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Int(calories).formatted()).font(.system(size: 51, weight: .heavy, design: .rounded)).contentTransition(.numericText())
                Text("/ \(fit.goals.calories) kcal").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            }
            ProgressStripe(value: calories, goal: Double(fit.goals.calories), color: .white)
            HStack {
                Text("\(max(0, fit.goals.calories - Int(calories))) kcal remaining")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button { selectedTab = 1 } label: {
                    HStack(spacing: 5) { Text("Log food"); Image(systemName: "arrow.up.right") }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.white, in: Capsule()).foregroundStyle(FitStyle.bg)
                }
            }
        }
        .padding(22)
        .background(LinearGradient(colors: [FitStyle.orange, Color(red: 0.69, green: 0.20, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }

    private func macroTile(_ title: String, amount: Double, goal: Double, color: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SmallLabel(text: title)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Int(amount).formatted()).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(unit).font(.caption2).foregroundStyle(FitStyle.muted)
            }
            ProgressStripe(value: amount, goal: goal, color: color)
            Text("of \(Int(goal))g").font(.system(size: 10)).foregroundStyle(FitStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
    }

    private func healthTile(_ label: String, icon: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.subheadline.weight(.semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(FitStyle.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hydration", systemImage: "drop.fill").font(.headline)
                Spacer()
                Text("\(fit.water(on: today)) / \(fit.goals.water) ml").font(.subheadline.monospacedDigit()).foregroundStyle(FitStyle.muted)
            }
            ProgressStripe(value: Double(fit.water(on: today)), goal: Double(fit.goals.water), color: FitStyle.blue)
            HStack(spacing: 10) {
                ForEach([250, 500], id: \.self) { amount in
                    Button { fit.water.append(WaterEntry(amount: amount)) } label: {
                        Label("+\(amount) ml", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(FitStyle.bg, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        }.fitCard()
    }

    private var trainingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "dumbbell.fill").font(.title).foregroundStyle(FitStyle.orange)
                .frame(width: 54, height: 54).background(FitStyle.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text(fit.currentWorkout == nil ? "Ready to train?" : "Session in progress").font(.headline)
                Text(fit.currentWorkout ?? "Push, pull, legs and more").font(.caption).foregroundStyle(FitStyle.muted).lineLimit(1)
            }
            Spacer()
            Button { selectedTab = 2 } label: { Image(systemName: "arrow.right").font(.headline).foregroundStyle(.black).frame(width: 38, height: 38).background(FitStyle.mint, in: Circle()) }
        }.fitCard()
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("7 DAY INTAKE").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5)
                Spacer()
                Text("kcal logged").font(.caption2).foregroundStyle(FitStyle.muted)
            }
            Chart {
                ForEach(0..<7, id: \.self) { i in
                    let d = Calendar.current.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
                    BarMark(x: .value("Day", d, unit: .day), y: .value("Calories", fit.kcal(on: d)))
                        .foregroundStyle(FitStyle.orange.gradient)
                        .cornerRadius(5)
                }
                RuleMark(y: .value("Goal", fit.goals.calories))
                    .foregroundStyle(FitStyle.muted.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 154)
        }.fitCard()
    }
}
