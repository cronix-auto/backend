import SwiftUI

struct TrainingScreen: View {
    @EnvironmentObject var data: FitnessStore
    @EnvironmentObject var health: HealthBridge
    @AppStorage("fit.syncWorkoutsToHealth") private var syncWorkouts = false
    @State private var exercise = ""
    @State private var kg = "20"
    @State private var reps = "10"

    private var activeSets: [LiftRecord] {
        guard let started = data.activeSince else { return [] }
        return data.lifts.filter { $0.date >= started }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FitHeader(title: "Train with intent.", subtitle: "Log every set. Beat your previous session.")
                if let name = data.activeName {
                    FitCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("SESSION IN PROGRESS").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(FitStyle.lime)
                                Text(name).font(.system(size: 28, weight: .bold, design: .rounded))
                                Text("\(activeSets.count) sets recorded").font(.caption).foregroundStyle(FitStyle.muted)
                            }
                            Spacer()
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 35)).foregroundStyle(FitStyle.lime)
                        }
                        if name != "Cardio" {
                            Text("CHOOSE AN EXERCISE").font(.caption.weight(.bold)).foregroundStyle(FitStyle.muted).padding(.top, 11)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(data.activeExercises, id: \.self) { move in
                                        Button { exercise = move } label: {
                                            Text(move).font(.caption.weight(.semibold))
                                                .foregroundStyle(exercise == move ? FitStyle.bg : .white)
                                                .padding(.horizontal, 12).padding(.vertical, 10)
                                                .background(exercise == move ? FitStyle.lime : FitStyle.card2, in: Capsule())
                                        }
                                    }
                                }
                            }
                            TextField("Exercise", text: $exercise)
                                .padding(12)
                                .background(FitStyle.card2, in: RoundedRectangle(cornerRadius: 12))
                                .padding(.top, 5)
                            HStack(spacing: 10) {
                                numericInput("WEIGHT KG", text: $kg)
                                numericInput("REPS", text: $reps)
                            }.padding(.top, 5)
                            Button {
                                let enteredKg = max(0, Double(kg.replacingOccurrences(of: ",", with: ".")) ?? 0)
                                let enteredReps = max(0, Int(reps) ?? 0)
                                guard !exercise.trimmingCharacters(in: .whitespaces).isEmpty, enteredReps > 0 else { return }
                                data.lifts.insert(LiftRecord(exercise: exercise, kg: enteredKg, reps: enteredReps), at: 0)
                            } label: {
                                Label("Add set", systemImage: "plus.circle.fill")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(FitStyle.lime, in: RoundedRectangle(cornerRadius: 13))
                                    .foregroundStyle(FitStyle.bg)
                            }.padding(.top, 8)
                        } else {
                            Label("Walk, cycle or use an incline treadmill. Finish to record your workout duration.", systemImage: "figure.walk")
                                .font(.subheadline).foregroundStyle(FitStyle.muted).padding(.vertical, 20)
                        }
                        HStack {
                            Button("Discard") { data.cancelWorkout() }
                                .foregroundStyle(FitStyle.muted)
                            Spacer()
                            Button("Finish workout") {
                                if let record = data.finish(), syncWorkouts { health.saveWorkout(record) }
                                exercise = ""
                            }
                            .font(.subheadline.weight(.bold)).foregroundStyle(FitStyle.lime)
                        }.padding(.top, 8)
                    }
                    if !activeSets.isEmpty {
                        Text("SESSION SETS").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(FitStyle.muted)
                        ForEach(activeSets) { set in
                            HStack {
                                Text(set.exercise).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(set.kg.formatted()) kg × \(set.reps)").foregroundStyle(FitStyle.lime).font(.subheadline.weight(.bold))
                            }.padding(14).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                } else {
                    HStack {
                        Text("START A SESSION").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted)
                        Spacer()
                        Text("Your split").font(.caption).foregroundStyle(FitStyle.lime)
                    }
                    ForEach(WorkoutPreset.all) { preset in
                        Button {
                            data.start(preset)
                            exercise = preset.exercises.first ?? ""
                        } label: {
                            HStack(spacing: 15) {
                                Image(systemName: preset.symbol)
                                    .font(.title2).foregroundStyle(FitStyle.lime)
                                    .frame(width: 55, height: 55)
                                    .background(FitStyle.card2, in: RoundedRectangle(cornerRadius: 16))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(preset.name).font(.headline).foregroundStyle(.white)
                                    Text(preset.subtitle).font(.caption).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(FitStyle.lime)
                            }.padding(15).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
                Text("RECENT WORKOUTS").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted).padding(.top, 6)
                if data.workouts.isEmpty {
                    FitCard {
                        Label("Your completed sessions will show here.", systemImage: "calendar")
                            .font(.subheadline).foregroundStyle(FitStyle.muted)
                    }
                } else {
                    ForEach(Array(data.workouts.prefix(7))) { workout in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(FitStyle.lime)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.name).font(.subheadline.weight(.bold))
                                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(FitStyle.muted)
                            }
                            Spacer()
                            Text("\(workout.minutes) min · \(workout.sets) sets").font(.caption).foregroundStyle(FitStyle.muted)
                        }.padding(13).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Text("Strength templates include back, legs and rear delts for balanced training.")
                    .font(.caption2).foregroundStyle(FitStyle.muted).padding(.bottom, 30)
            }.padding(.horizontal, 19).padding(.top, 17)
        }.background(FitStyle.bg.ignoresSafeArea())
    }

    private func numericInput(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(FitStyle.muted)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .background(FitStyle.card2, in: RoundedRectangle(cornerRadius: 12))
        }.frame(maxWidth: .infinity)
    }
}
