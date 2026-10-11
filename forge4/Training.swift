import SwiftUI

struct TrainPage: View {
    @EnvironmentObject private var data: FitStore
    @State private var selectedTemplate = 0
    @State private var customSession = ""
    @State private var exercise = "Incline DB press"
    @State private var customExercise = ""
    @State private var kilograms = "20"
    @State private var repetitions = "8"
    @State private var rir = -1
    @State private var warmup = false
    @State private var setNote = ""
    @State private var restEnd: Date?
    @State private var sessionDetail: WorkoutEntry?
    @State private var showCancel = false

    private var exerciseName: String {
        let text = customExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? exercise : text
    }
    private var validSet: Bool {
        let kg = Double(kilograms.replacingOccurrences(of: ",", with: ".")) ?? -1
        let reps = Int(repetitions) ?? 0
        return !exerciseName.isEmpty && kg >= 0 && kg <= 1000 && reps > 0 && reps <= 100
    }
    private var activeVolume: Double { data.activeSets.reduce(0) { $0 + $1.volume } }
    private var planned: [String] {
        guard data.currentWorkout != nil else { return [] }
        let matching = ExerciseLibrary.templates.first { $0.0 == data.currentWorkout }
        return matching?.1 ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHead(title: "Training", subtitle: "Log each working set. Keep the numbers honest.")
                    if let sessionName = data.currentWorkout {
                        activeWorkout(sessionName)
                    } else {
                        beginWorkout
                    }
                    HStack {
                        Text("History").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Text("\(data.workouts.count) sessions")
                            .font(.system(size: 12)).foregroundStyle(Forge.muted)
                    }
                    if data.workouts.isEmpty {
                        EmptyLog(icon: "dumbbell", title: "No completed sessions",
                                 detail: "Record your sets and finish a workout to build your history.")
                    } else {
                        ForEach(data.workouts.sorted { $0.date > $1.date }.prefix(25)) { session in
                            Button { sessionDetail = session } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "dumbbell")
                                        .font(.system(size: 16)).foregroundStyle(Forge.paleBlue)
                                        .frame(width: 37, height: 37)
                                        .background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.name).font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(session.date.dayTitle).font(.system(size: 11))
                                            .foregroundStyle(Forge.muted)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(session.sets.filter(\.working).count) sets")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("\(session.minutes) min")
                                            .font(.system(size: 11)).foregroundStyle(Forge.muted)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2).foregroundStyle(Forge.muted)
                                }.padding(13).background(Forge.panel, in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }.forgePage()
            .sheet(item: $sessionDetail) { entry in SessionDetail(entry: entry) }
            .alert("Discard this session?", isPresented: $showCancel) {
                Button("Discard", role: .destructive) { data.clearSession(); restEnd = nil }
                Button("Keep training", role: .cancel) { }
            } message: { Text("Unsaved sets from this workout will be lost.") }
        }
    }

    private var beginWorkout: some View {
        VStack(alignment: .leading, spacing: 14) {
            TinyLabel(text: "Choose a workout")
            ForEach(ExerciseLibrary.templates.indices, id: \.self) { index in
                let item = ExerciseLibrary.templates[index]
                Button { selectedTemplate = index } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedTemplate == index ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedTemplate == index ? Forge.paleBlue : Forge.muted)
                        Text(item.0).font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(index == 5 ? "Empty" : "\(item.1.count) exercises")
                            .font(.system(size: 11)).foregroundStyle(Forge.muted)
                    }
                    .padding(13)
                    .background(selectedTemplate == index ? Forge.darkBlue : Forge.inset,
                                in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            if selectedTemplate == 5 {
                TextField("Session name (optional)", text: $customSession)
                    .font(.system(size: 14)).padding(13)
                    .background(Forge.inset, in: RoundedRectangle(cornerRadius: 10))
            }
            SolidAction(title: "Start workout", symbol: "play.fill") {
                let name = selectedTemplate == 5 ?
                    (customSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : customSession) :
                    ExerciseLibrary.templates[selectedTemplate].0
                data.begin(name)
                exercise = ExerciseLibrary.templates[selectedTemplate].1.first ?? ExerciseLibrary.all[0].name
                restEnd = nil
            }
        }.surface()
    }

    private func activeWorkout(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    TinyLabel(text: "Session in progress")
                    Spacer()
                    Text(data.startedAt?.formatted(.dateTime.hour().minute()) ?? "")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Forge.muted)
                }
                Text(name).font(.system(size: 24, weight: .semibold))
                HStack(spacing: 10) {
                    littleStat("\(data.workingSets.count)", "Working sets")
                    littleStat("\(Int(activeVolume).formatted())", "Volume kg")
                    littleStat("\(data.activeSets.count)", "All sets")
                }
                restTimer
                HStack(spacing: 6) {
                    TinyLabel(text: "Rest")
                    Spacer(minLength: 3)
                    ForEach([60, 90, 120, 180], id: \.self) { seconds in
                        Button {
                            data.goals.restSeconds = seconds
                        } label: {
                            Text("\(seconds / 60):\(seconds % 60 == 0 ? "00" : "30")")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle((data.goals.restSeconds ?? 90) == seconds ? .white : Forge.muted)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background((data.goals.restSeconds ?? 90) == seconds ? Forge.blue : Forge.inset, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.surface()

            VStack(alignment: .leading, spacing: 14) {
                TinyLabel(text: "Log a set")
                if !planned.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(planned, id: \.self) { item in
                                Button {
                                    exercise = item
                                    customExercise = ""
                                } label: {
                                    Text(item).font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(exerciseName == item ? .white : Forge.paleBlue)
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(exerciseName == item ? Forge.blue : Forge.darkBlue,
                                                    in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Text("Exercise").font(.system(size: 13)).foregroundStyle(Forge.muted)
                    Spacer()
                    Picker("Exercise", selection: $exercise) {
                        ForEach(ExerciseLibrary.all) { item in
                            Text(item.name).tag(item.name)
                        }
                    }.labelsHidden().tint(Forge.paleBlue)
                        .frame(maxWidth: 210, alignment: .trailing)
                }
                TextField("Or type a custom exercise", text: $customExercise)
                    .font(.system(size: 13)).padding(12)
                    .background(Forge.inset, in: RoundedRectangle(cornerRadius: 10))
                previousPerformance
                HStack(spacing: 12) {
                    InsetField(label: "Weight", value: $kilograms, suffix: "kg")
                    InsetField(label: "Reps", value: $repetitions, suffix: "", decimal: false)
                }
                HStack {
                    Toggle("Warm-up set", isOn: $warmup)
                        .font(.system(size: 13)).tint(Forge.blue)
                    Spacer()
                    if !warmup {
                        Picker("RIR", selection: $rir) {
                            Text("RIR —").tag(-1)
                            ForEach(0...5, id: \.self) { i in Text("RIR \(i)").tag(i) }
                        }.font(.system(size: 12)).tint(Forge.paleBlue)
                    }
                }
                TextField("Set note (optional)", text: $setNote)
                    .font(.system(size: 13)).padding(12)
                    .background(Forge.inset, in: RoundedRectangle(cornerRadius: 10))
                SolidAction(title: "Add set", symbol: "plus", enabled: validSet) { logSet() }
            }.surface()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sets logged").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("\(data.activeSets.count) total").font(.caption)
                        .foregroundStyle(Forge.muted)
                }
                if data.activeSets.isEmpty {
                    Text("Your first set will show here.")
                        .font(.system(size: 13)).foregroundStyle(Forge.muted)
                        .padding(.vertical, 12)
                }
                ForEach(Array(data.activeSets.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Forge.muted).frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.exercise).font(.system(size: 13, weight: .medium))
                            Text(entry.isWarmup == true ? "Warm-up" :
                                    (entry.rir.map { "RIR \($0)" } ?? "Working set"))
                                .font(.system(size: 10)).foregroundStyle(Forge.muted)
                        }
                        Spacer()
                        Text("\(entry.kg.short) kg × \(entry.reps)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                        Button {
                            data.activeSets.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(Forge.muted)
                        }.buttonStyle(.plain)
                    }
                    if index < data.activeSets.count - 1 {
                        Rectangle().fill(Forge.line).frame(height: 0.5)
                    }
                }
            }.surface()

            VStack(alignment: .leading, spacing: 12) {
                TinyLabel(text: "Session notes")
                TextField("What changed today?", text: $data.activeNotes, axis: .vertical)
                    .lineLimit(2...5).font(.system(size: 13))
                    .padding(12).background(Forge.inset, in: RoundedRectangle(cornerRadius: 10))
                SolidAction(title: "Finish workout", symbol: "checkmark", enabled: !data.activeSets.isEmpty) {
                    data.finish()
                    restEnd = nil
                }
                Button("Discard session") { showCancel = true }
                    .font(.system(size: 12)).foregroundStyle(Forge.muted)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }.surface()
        }
    }

    private var previousPerformance: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let prev = data.previousSets(for: exerciseName).filter(\.working).max(by: { $0.kg < $1.kg }) {
                HStack {
                    Text("LAST SESSION   \(prev.kg.short) kg × \(prev.reps)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Forge.paleBlue)
                    Spacer()
                    Button("LOAD LAST") {
                        kilograms = prev.kg.short
                        repetitions = String(prev.reps)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Forge.paleBlue)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 7))
                }
            } else {
                Text("No previous working sets for this exercise")
                    .font(.system(size: 11)).foregroundStyle(Forge.muted)
            }
            if let best = data.bestSet(for: exerciseName), best.estimatedMax > 0 {
                Text("BEST EST. 1RM   \(best.estimatedMax.short) kg")
                    .font(.system(size: 11)).foregroundStyle(Forge.muted)
            }
        }
    }

    @ViewBuilder private var restTimer: some View {
        if let end = restEnd {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                HStack {
                    Image(systemName: "timer").foregroundStyle(Forge.paleBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest timer").font(.system(size: 11)).foregroundStyle(Forge.muted)
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    Button("+15") { restEnd = end.addingTimeInterval(15) }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(9).background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 9))
                    Button("Skip") { restEnd = nil }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(9).background(Forge.inset, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        } else {
            HStack {
                Image(systemName: "timer").foregroundStyle(Forge.paleBlue)
                Text("Rest timer starts after each set")
                    .font(.system(size: 12)).foregroundStyle(Forge.muted)
            }
        }
    }

    private func littleStat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 10)).foregroundStyle(Forge.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(11).background(Forge.inset, in: RoundedRectangle(cornerRadius: 11))
    }
    private func logSet() {
        guard validSet else { return }
        guard let kg = Double(kilograms.replacingOccurrences(of: ",", with: ".")),
              let reps = Int(repetitions) else { return }
        data.activeSets.append(LiftSet(
            exercise: exerciseName, kg: kg, reps: reps,
            rir: warmup || rir < 0 ? nil : rir,
            isWarmup: warmup,
            note: setNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : setNote
        ))
        setNote = ""
        restEnd = Date().addingTimeInterval(TimeInterval(data.goals.restSeconds ?? 90))
    }
}

struct SessionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let entry: WorkoutEntry
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHead(title: entry.name, subtitle: entry.date.formatted(date: .complete, time: .shortened))
                    HStack {
                        Text("\(entry.minutes) min")
                        Spacer()
                        Text("\(entry.sets.filter(\.working).count) working sets")
                        Spacer()
                        Text("\(Int(entry.sets.reduce(0) { $0 + $1.volume })) kg")
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(Forge.muted)
                        .surface()
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(Forge.muted)
                                .frame(width: 24, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(set.exercise).font(.system(size: 14, weight: .medium))
                                Text(set.working ? "Working" : "Warm-up")
                                    .font(.system(size: 11)).foregroundStyle(Forge.muted)
                                if let note = set.note, !note.isEmpty {
                                    Text(note).font(.system(size: 11)).foregroundStyle(Forge.muted)
                                }
                            }
                            Spacer()
                            Text("\(set.kg.short) × \(set.reps)")
                                .font(.system(size: 14, weight: .semibold))
                        }.surface(12)
                    }
                    if let notes = entry.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            TinyLabel(text: "Notes")
                            Text(notes).font(.subheadline)
                        }.surface()
                    }
                }.padding(.horizontal, 18).padding(.bottom, 20)
            }.forgePage()
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.tint(Forge.paleBlue)
            }}
        }
    }
}
