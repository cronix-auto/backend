import SwiftUI

struct HomePage: View {
    @EnvironmentObject private var data: FitStore
    @Binding var selection: Int
    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("FORGE")
                                .font(.system(size: 14, weight: .black))
                                .tracking(3).foregroundStyle(Forge.paleBlue)
                            Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                        }
                        Spacer()
                        Text("TODAY").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Forge.paleBlue)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Forge.darkBlue, in: Capsule())
                    }.padding(.top, 12)

                    VStack(alignment: .leading, spacing: 17) {
                        TinyLabel(text: "Calorie budget")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(max(0, data.goals.calories - Int(data.kcal(on: today))))")
                                .font(.system(size: 50, weight: .bold, design: .rounded))
                                .tracking(-1.8).contentTransition(.numericText())
                            Text("kcal left").font(.system(size: 14)).foregroundStyle(Forge.muted)
                            Spacer()
                        }
                        Meter(current: data.kcal(on: today), target: Double(data.goals.calories), height: 9)
                        HStack {
                            Text("\(Int(data.kcal(on: today))) eaten")
                            Spacer()
                            Text("\(data.goals.calories) target")
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(Forge.muted)
                        if data.kcal(on: today) > Double(data.goals.calories) {
                            Text("\(Int(data.kcal(on: today)) - data.goals.calories) kcal over target")
                                .font(.caption).foregroundStyle(Forge.paleBlue)
                        }
                    }.surface()

                    HStack(spacing: 10) {
                        macroTile("Protein", value: data.protein(on: today), goal: data.goals.protein, suffix: "g")
                        macroTile("Carbs", value: data.carbs(on: today), goal: data.goals.carbs, suffix: "g")
                        macroTile("Fat", value: data.fat(on: today), goal: data.goals.fat, suffix: "g")
                    }

                    HStack(spacing: 10) {
                        SolidAction(title: "Log food", symbol: "plus") { selection = 1 }
                        SolidAction(title: data.currentWorkout == nil ? "Start workout" : "Open workout",
                                    symbol: "dumbbell.fill") { selection = 2 }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Water").font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Text("\(data.water(on: today)) / \(data.goals.water) ml")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Forge.muted)
                        }
                        Meter(current: Double(data.water(on: today)), target: Double(data.goals.water))
                        HStack(spacing: 10) {
                            ForEach([250, 500], id: \.self) { amount in
                                Button {
                                    data.water.append(WaterEntry(amount: amount))
                                } label: {
                                    Text("+\(amount) ml").font(.system(size: 13, weight: .semibold))
                                        .frame(maxWidth: .infinity).frame(height: 37)
                                        .background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                            Button {
                                if let i = data.water.lastIndex(where: {
                                    Calendar.current.isDateInToday($0.date)
                                }) { data.water.remove(at: i) }
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .frame(width: 45, height: 37)
                                    .background(Forge.inset, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(data.water(on: today) == 0)
                        }
                    }.surface()

                    HStack {
                        Text("Training").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(data.weekCount()) this week")
                            .font(.system(size: 12)).foregroundStyle(Forge.muted)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 18))
                            .foregroundStyle(Forge.paleBlue)
                            .frame(width: 44, height: 44)
                            .background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(data.currentWorkout ?? data.workouts.first?.name ?? "No workout logged")
                                .font(.system(size: 14, weight: .semibold))
                            Text(data.currentWorkout != nil ? "Session in progress" :
                                 data.workouts.first?.date.dayTitle ?? "Begin a session to track sets")
                                .font(.system(size: 12)).foregroundStyle(Forge.muted)
                        }
                        Spacer()
                        Button { selection = 2 } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Forge.inset, in: Circle())
                        }.buttonStyle(.plain)
                    }.surface()

                    HStack {
                        Text("Food log").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Button("View all") { selection = 1 }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Forge.paleBlue)
                    }
                    if data.meals(on: today).isEmpty {
                        EmptyLog(icon: "fork.knife", title: "No meals logged",
                                 detail: "Add food by weight or use a saved reference.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(data.meals(on: today).suffix(4).reversed())) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text(item.mealType ?? "Food")
                                            .font(.system(size: 11)).foregroundStyle(Forge.muted)
                                    }
                                    Spacer()
                                    Text("\(Int(item.calories.rounded())) kcal")
                                        .font(.system(size: 13, weight: .semibold))
                                        .monospacedDigit()
                                }.padding(.vertical, 12)
                                if item.id != data.meals(on: today).first?.id {
                                    Rectangle().fill(Forge.line).frame(height: 0.5)
                                }
                            }
                        }.surface()
                    }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }.forgePage()
        }
    }

    private func macroTile(_ name: String, value: Double, goal: Int, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TinyLabel(text: name)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.8).lineLimit(1)
                Text(suffix).font(.caption2).foregroundStyle(Forge.muted)
            }
            Meter(current: value, target: Double(goal), height: 5)
            Text("/ \(goal)g").font(.system(size: 11)).foregroundStyle(Forge.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .surface()
    }
}
