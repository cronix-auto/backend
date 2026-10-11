import SwiftUI

struct GoalsPage: View {
    @EnvironmentObject private var data: FitStore
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var water = ""
    @State private var weight = ""
    @State private var rest = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHead(title: "Settings", subtitle: "Your targets, your training.")
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Daily nutrition").font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 12) {
                            InsetField(label: "Calories", value: $calories, suffix: "kcal", decimal: false)
                            InsetField(label: "Protein", value: $protein, suffix: "g", decimal: false)
                        }
                        HStack(spacing: 12) {
                            InsetField(label: "Carbs", value: $carbs, suffix: "g", decimal: false)
                            InsetField(label: "Fat", value: $fat, suffix: "g", decimal: false)
                        }
                    }.surface()
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Body & hydration").font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 12) {
                            InsetField(label: "Water target", value: $water, suffix: "ml", decimal: false)
                            InsetField(label: "Weight goal", value: $weight, suffix: "kg")
                        }
                    }.surface()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Training").font(.system(size: 17, weight: .semibold))
                        InsetField(label: "Rest timer after a set", value: $rest, suffix: "sec", decimal: false)
                        Text("The timer starts automatically each time you log a set. You can skip or extend it.")
                            .font(.system(size: 11)).foregroundStyle(Forge.muted)
                    }.surface()
                    SolidAction(title: saved ? "Changes saved" : "Save settings",
                                symbol: saved ? "checkmark.circle.fill" : "checkmark") {
                        save()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        TinyLabel(text: "Logging guidance")
                        Text("Use cooked weight for cooked food entries and raw weight for raw food entries.")
                        Text("Choose exact package nutrition for branded foods and cooking oils.")
                        Text("Weight trends work best with consistent morning weigh-ins. Training estimates are not measured maximums.")
                    }.font(.system(size: 12)).foregroundStyle(Forge.muted).surface()
                    Text("FORGE 4.0")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4).foregroundStyle(Forge.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }.forgePage()
            .onAppear(perform: load)
        }
    }

    private func load() {
        calories = String(data.goals.calories)
        protein = String(data.goals.protein)
        carbs = String(data.goals.carbs)
        fat = String(data.goals.fat)
        water = String(data.goals.water)
        weight = data.goals.targetKg.short
        rest = String(data.goals.restSeconds ?? 90)
        saved = false
    }
    private func save() {
        var g = data.goals
        if let n = Int(calories), (1000...6000).contains(n) { g.calories = n }
        if let n = Int(protein), (0...400).contains(n) { g.protein = n }
        if let n = Int(carbs), (0...800).contains(n) { g.carbs = n }
        if let n = Int(fat), (0...300).contains(n) { g.fat = n }
        if let n = Int(water), (250...8000).contains(n) { g.water = n }
        if let n = Double(weight.replacingOccurrences(of: ",", with: ".")), (35...350).contains(n) {
            g.targetKg = n
        }
        if let n = Int(rest), (15...600).contains(n) { g.restSeconds = n }
        data.goals = g
        load()
        saved = true
    }
}
