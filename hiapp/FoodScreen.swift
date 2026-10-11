import SwiftUI

struct FoodScreen: View {
    @EnvironmentObject var data: FitnessStore
    @State private var query = ""
    @State private var selected: FoodPreset?
    @State private var customEntry = false
    private var matches: [FoodPreset] {
        query.isEmpty ? FoodPreset.all : FoodPreset.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FitHeader(title: "Fuel your progress.", subtitle: "Simple, accurate-enough tracking you can edit.")
                    HStack(spacing: 10) {
                        MetricTile(icon: "flame.fill", value: "\(Int(data.caloriesOn()))", title: "Kcal eaten", tint: FitStyle.orange)
                        MetricTile(icon: "bolt.fill", value: "\(Int(data.proteinOn())) g", title: "Protein today", tint: FitStyle.lime)
                    }
                    HStack {
                        Text("QUICK ADD").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(FitStyle.muted)
                        Spacer()
                        Button { customEntry = true } label: {
                            Label("Custom food", systemImage: "plus").font(.caption.weight(.bold)).foregroundStyle(FitStyle.lime)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(FitStyle.muted)
                        TextField("Search your staples", text: $query)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                    }
                    .padding(14).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 15))
                    ForEach(matches) { food in
                        Button { selected = food } label: {
                            HStack(spacing: 13) {
                                Image(systemName: food.name == "Chicken breast" ? "fork.knife" : "plus.circle.fill")
                                    .font(.title3).foregroundStyle(FitStyle.lime)
                                    .frame(width: 37, height: 37)
                                    .background(FitStyle.card2, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(food.portion).font(.caption).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(Int(food.calories)) kcal").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text("\(Int(food.protein))g protein").font(.caption).foregroundStyle(FitStyle.muted)
                                }
                            }
                            .padding(14)
                            .background(FitStyle.card, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("TODAY'S FOOD").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(FitStyle.muted).padding(.top, 4)
                    if data.foodsOn().isEmpty {
                        FitCard {
                            Label("Nothing logged yet. Start with a staple above.", systemImage: "leaf")
                                .font(.subheadline).foregroundStyle(FitStyle.muted)
                        }
                    } else {
                        ForEach(data.foodsOn().sorted { $0.date > $1.date }) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.subheadline.weight(.semibold))
                                    Text("\(Int(item.protein))g P · \(Int(item.carbs))g C · \(Int(item.fat))g F").font(.caption).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                Text("\(Int(item.calories)) kcal").foregroundStyle(FitStyle.lime).font(.subheadline.weight(.bold))
                                Button(role: .destructive) { data.foods.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "trash").foregroundStyle(FitStyle.muted)
                                }.padding(.leading, 6)
                            }
                            .padding(14).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    Text("Nutrition presets are approximations. Check the label, especially for protein milk and yogurt.")
                        .font(.caption2).foregroundStyle(FitStyle.muted).padding(.bottom, 30)
                }.padding(.horizontal, 19).padding(.top, 17)
            }
            .background(FitStyle.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { preset in FoodEntrySheet(preset: preset) }
            .sheet(isPresented: $customEntry) { FoodEntrySheet(preset: nil) }
        }
    }
}

struct FoodEntrySheet: View {
    let preset: FoodPreset?
    @EnvironmentObject var data: FitnessStore
    @EnvironmentObject var health: HealthBridge
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fit.syncFoodToHealth") private var syncFood = false
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var servings = 1.0

    private func number(_ text: String) -> Double { max(0, Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Food name", text: $name)
                    if let preset {
                        LabeledContent("Reference serving", value: preset.portion)
                        Stepper("Servings: \(servings.formatted(.number.precision(.fractionLength(1))))", value: $servings, in: 0.5...10, step: 0.5)
                    }
                }
                Section("Nutrition per serving") {
                    row("Calories (kcal)", value: $kcal)
                    row("Protein (g)", value: $protein)
                    row("Carbs (g)", value: $carbs)
                    row("Fat (g)", value: $fat)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total: \(Int(number(kcal) * servings)) kcal · \(Int(number(protein) * servings))g protein")
                            .font(.headline)
                        Text("You can edit preset values to match your packaging. Food is saved on this iPhone.")
                            .font(.caption).foregroundStyle(FitStyle.muted)
                    }
                }
                Section {
                    Button("Save food") {
                        let entry = FoodRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines), calories: number(kcal) * servings, protein: number(protein) * servings, carbs: number(carbs) * servings, fat: number(fat) * servings)
                        data.foods.insert(entry, at: 0)
                        if syncFood { health.saveFood(entry) }
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(FitStyle.lime)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || number(kcal) <= 0)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FitStyle.bg)
            .navigationTitle(preset == nil ? "Custom food" : "Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard let preset else { return }
                name = preset.name; kcal = String(preset.calories); protein = String(preset.protein)
                carbs = String(preset.carbs); fat = String(preset.fat)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func row(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }
}
