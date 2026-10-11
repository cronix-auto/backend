import SwiftUI

enum LiftLibrary {
    static let templates = ["Upper / Push", "Upper / Pull", "Legs + Core", "Arms + Delts", "Full Body", "Custom Session"]
    static let exercises = [
        "Incline Dumbbell Press", "Flat Bench Press", "Overhead Press", "Lateral Raise",
        "Rear Delt Fly", "Cable Fly", "Lat Pulldown", "Seated Row", "Chest Supported Row",
        "Pull-up", "Barbell Row", "Preacher Curl", "Dumbbell Curl", "Hammer Curl",
        "Triceps Pushdown", "Overhead Triceps Extension", "Squat", "Leg Press",
        "Romanian Deadlift", "Leg Curl", "Leg Extension", "Calf Raise", "Crunch", "Plank"
    ]
}

struct TrainingView: View {
    @EnvironmentObject var fit: FitStore
    @State private var selectedTemplate = "Upper / Push"
    @State private var exercise = "Incline Dumbbell Press"
    @State private var customExercise = ""
    @State private var weight = 20.0
    @State private var reps = 8
    @State private var showingHistory = false

    private var exerciseName: String {
        let custom = customExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? exercise : custom
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        Headline(label: "Training", detail: "Build strength")
                        Spacer()
                        Image(systemName: "dumbbell.fill").font(.system(size: 33)).foregroundStyle(FitStyle.orange)
                    }.padding(.top, 10)
                    if fit.currentWorkout == nil { startView } else { activeView }
                    stats
                    HStack {
                        Text("RECENT SESSIONS").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5)
                        Spacer()
                        Text("\(fit.workouts.count) total").font(.caption).foregroundStyle(FitStyle.muted)
                    }.padding(.top, 8)
                    if fit.workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your training history starts here").font(.headline)
                            Text("Log weights, reps and sets to build a personal record of your lifts.").foregroundStyle(FitStyle.muted).font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
                    }
                    ForEach(fit.workouts.prefix(30)) { session in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name).font(.headline)
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                Text("\(session.sets.count) sets").font(.subheadline.weight(.bold)).foregroundStyle(FitStyle.mint)
                            }
                            HStack {
                                Label("\(session.minutes) min", systemImage: "clock")
                                Spacer()
                                Label("\(Int(session.sets.reduce(0.0) { $0 + $1.kg * Double($1.reps) })) kg volume", systemImage: "chart.bar.fill")
                            }.font(.caption).foregroundStyle(FitStyle.muted)
                            ForEach(session.sets.prefix(4)) { lift in
                                Text("\(lift.exercise)   ·   \(lift.kg.formatted()) kg × \(lift.reps)")
                                    .font(.caption2).foregroundStyle(FitStyle.muted)
                            }
                            if session.sets.count > 4 {
                                Text("+ \(session.sets.count - 4) more sets").font(.caption2).foregroundStyle(FitStyle.muted)
                            }
                        }.fitCard()
                    }
                }.padding(18)
            }.background(FitStyle.bg).toolbar(.hidden, for: .navigationBar)
        }
    }

    private var startView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SmallLabel(text: "Select session")
                Text("Strong today. Stronger tomorrow.").font(.title3.bold())
                Text("Balance your pressing with back, legs and rear-delts work.")
                    .font(.caption).foregroundStyle(FitStyle.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(LiftLibrary.templates, id: \.self) { name in
                    Button { selectedTemplate = name } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: name == selectedTemplate ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(name == selectedTemplate ? FitStyle.orange : FitStyle.muted)
                            Text(name).font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .padding(12)
                        .background(name == selectedTemplate ? FitStyle.orange.opacity(0.12) : FitStyle.bg, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(name == selectedTemplate ? FitStyle.orange.opacity(0.6) : FitStyle.line))
                    }.buttonStyle(.plain)
                }
            }
            Button { fit.begin(selectedTemplate) } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(15)
                    .background(FitStyle.orange, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }.fitCard()
    }

    private var activeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    SmallLabel(text: "Live workout")
                    Text(fit.currentWorkout ?? "Session").font(.title2.bold())
                }
                Spacer()
                Text("\(fit.activeSets.count) sets").font(.subheadline.bold()).foregroundStyle(FitStyle.mint)
            }
            Divider().overlay(FitStyle.line)
            VStack(alignment: .leading, spacing: 6) {
                SmallLabel(text: "Exercise")
                Picker("Exercise", selection: $exercise) {
                    ForEach(LiftLibrary.exercises, id: \.self) { Text($0).tag($0) }
                }
                .tint(FitStyle.mint).frame(maxWidth: .infinity, alignment: .leading)
                TextField("Or type a custom exercise", text: $customExercise)
                    .textInputAutocapitalization(.words)
                    .padding(12).background(FitStyle.bg, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SmallLabel(text: "Weight, kg")
                    TextField("Weight", value: $weight, format: .number)
                        .keyboardType(.decimalPad).padding(12).background(FitStyle.bg, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 8) {
                    SmallLabel(text: "Reps")
                    Stepper("\(reps)", value: $reps, in: 1...100).font(.subheadline.bold())
                        .padding(10).background(FitStyle.bg, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button {
                fit.activeSets.append(LiftSet(exercise: exerciseName, kg: max(0, weight), reps: reps))
                customExercise = ""
            } label: {
                Label("Add set", systemImage: "plus.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(14)
                    .background(FitStyle.mint, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(FitStyle.bg)
            }
            if !fit.activeSets.isEmpty {
                ForEach(fit.activeSets.reversed()) { set in
                    HStack {
                        Text(set.exercise).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(set.kg.formatted()) kg × \(set.reps)").font(.caption.monospacedDigit())
                        Button { fit.activeSets.removeAll { $0.id == set.id } } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(FitStyle.muted)
                        }.accessibilityLabel("Remove set")
                    }.padding(.vertical, 3)
                }
            }
            Button { fit.finish() } label: {
                Label("Finish and save session", systemImage: "checkmark.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(15)
                    .background(FitStyle.orange, in: RoundedRectangle(cornerRadius: 14))
            }
        }.fitCard()
    }

    private var stats: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                SmallLabel(text: "Sessions logged")
                Text("\(fit.workouts.count)").font(.system(size: 29, weight: .bold, design: .rounded))
                Text("All time").font(.caption).foregroundStyle(FitStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
            VStack(alignment: .leading, spacing: 7) {
                SmallLabel(text: "Heaviest set")
                Text(fit.personalBest.map { String(format: "%.1f", $0.kg) } ?? "—")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(fit.personalBest?.exercise ?? "No sets logged").font(.caption).lineLimit(1).foregroundStyle(FitStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).fitCard()
        }
    }
}
