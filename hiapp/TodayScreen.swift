import SwiftUI

struct FitCard<Content: View>: View {
    @ViewBuilder let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitStyle.card, in: RoundedRectangle(cornerRadius: 23))
    }
}

struct FitHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 33, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(FitStyle.muted)
        }
    }
}

struct MetricTile: View {
    let icon: String
    let value: String
    let title: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(FitStyle.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FitStyle.card2, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MacroBar: View {
    let title: String
    let current: Double
    let goal: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.caption).foregroundStyle(FitStyle.muted)
                Spacer()
                Text("\(Int(current.rounded())) / \(Int(goal.rounded())) g").font(.caption).foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, current / max(1, goal))))
                }
            }.frame(height: 7)
        }
    }
}

struct TodayScreen: View {
    @EnvironmentObject var data: FitnessStore
    @EnvironmentObject var health: HealthBridge
    @Binding var tab: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.title2).foregroundStyle(FitStyle.bg)
                        .frame(width: 44, height: 44)
                        .background(FitStyle.lime, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FORGE").font(.system(size: 16, weight: .black, design: .rounded)).tracking(3)
                        Text(Date.now.formatted(date: .complete, time: .omitted)).font(.caption2).foregroundStyle(FitStyle.muted)
                    }
                    Spacer()
                    Button { tab = 4 } label: {
                        Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.white)
                    }
                }.padding(.top, 9)
                FitHeader(title: "Stronger, every day.", subtitle: "Your food, training and recovery in one place.")
                FitCard {
                    HStack(alignment: .center, spacing: 15) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.09), lineWidth: 12)
                            Circle()
                                .trim(from: 0, to: min(1, data.caloriesOn() / Double(max(1, data.calorieGoal))))
                                .stroke(FitStyle.lime, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Text("\(Int(data.caloriesOn()))")
                                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                                    .contentTransition(.numericText())
                                Text("EATEN").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(FitStyle.muted)
                            }
                        }.frame(width: 146, height: 146)
                        VStack(alignment: .leading, spacing: 11) {
                            Text("DAILY CALORIES").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(FitStyle.muted)
                            Text("\(max(0, data.calorieGoal - Int(data.caloriesOn())))")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(FitStyle.lime)
                            Text("kcal remaining").font(.caption).foregroundStyle(FitStyle.muted)
                            Text("Goal \(data.calorieGoal) kcal").font(.footnote.weight(.semibold))
                        }
                    }
                    Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 7)
                    VStack(spacing: 15) {
                        MacroBar(title: "Protein", current: data.proteinOn(), goal: Double(data.proteinGoal), color: FitStyle.lime)
                        MacroBar(title: "Carbs", current: data.carbsOn(), goal: Double(data.calorieGoal) * 0.40 / 4, color: FitStyle.orange)
                        MacroBar(title: "Fats", current: data.fatOn(), goal: Double(data.calorieGoal) * 0.30 / 9, color: .cyan)
                    }
                    Button { tab = 1 } label: {
                        Label("Log a meal", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .foregroundStyle(FitStyle.bg)
                            .background(FitStyle.lime, in: RoundedRectangle(cornerRadius: 14))
                    }.padding(.top, 8)
                }
                HStack {
                    Text("APPLE HEALTH").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted)
                    Spacer()
                    Button("Refresh") { health.refresh() }
                        .font(.caption.weight(.semibold)).foregroundStyle(FitStyle.lime)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(icon: "figure.walk", value: health.steps.map { $0.formatted() } ?? "—", title: "Steps today", tint: FitStyle.lime)
                    MetricTile(icon: "flame.fill", value: health.activeCalories.map { "\($0) kcal" } ?? "—", title: "Active energy", tint: FitStyle.orange)
                    MetricTile(icon: "moon.zzz.fill", value: health.sleepHours.map { String(format: "%.1f h", $0) } ?? "—", title: "Recent sleep", tint: .cyan)
                    MetricTile(icon: "heart.fill", value: health.restingBPM.map { "\($0) bpm" } ?? "—", title: "Resting heart rate", tint: .pink)
                }
                if !UserDefaults.standard.bool(forKey: "fit.healthRequested") {
                    Button { tab = 4 } label: {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                            Text("Connect Apple Health").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.white)
                        .padding(17)
                        .background(FitStyle.card, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                HStack {
                    Text("HYDRATION").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted)
                    Spacer()
                    Text("\(data.waterToday()) / \(data.waterGoal) ml").font(.caption.weight(.bold))
                }
                FitCard {
                    HStack(spacing: 14) {
                        Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stay hydrated").font(.headline)
                            ProgressView(value: min(1, Double(data.waterToday()) / Double(max(1, data.waterGoal)))).tint(.cyan)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("+250 ml") { data.addWater(250) }.buttonStyle(CompactPill())
                        Button("+500 ml") { data.addWater(500) }.buttonStyle(CompactPill())
                        Button("Undo") { data.addWater(-250) }.buttonStyle(CompactPill())
                    }
                }
                FitCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TODAY'S TRAINING").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(FitStyle.muted)
                            Text(data.activeName ?? "Ready for your next session?")
                                .font(.headline)
                            Text("\(data.setsToday()) sets logged · \(data.workoutsThisWeek()) sessions this week")
                                .font(.caption).foregroundStyle(FitStyle.muted)
                        }
                        Spacer()
                        Button { tab = 2 } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.title3.weight(.bold))
                                .frame(width: 42, height: 42)
                                .foregroundStyle(FitStyle.bg)
                                .background(FitStyle.lime, in: Circle())
                        }
                    }
                }
                Text("Food values are estimates. Use package labels for accuracy.")
                    .font(.caption2).foregroundStyle(FitStyle.muted)
                    .padding(.bottom, 22)
            }.padding(.horizontal, 19)
        }
        .background(FitStyle.bg.ignoresSafeArea())
    }
}

struct CompactPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(FitStyle.card2, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
