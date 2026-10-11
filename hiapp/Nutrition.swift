import SwiftUI

struct NutritionView: View {
    @EnvironmentObject var fit: FitStore
    @State private var day = Date()
    @State private var search = ""
    @State private var selectedFood: QuickFood?
    @State private var customOpen = false

    private var foods: [QuickFood] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? FoodCatalog.foods : FoodCatalog.foods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Headline(label: "Nutrition", detail: "Fuel the work")
                        Spacer()
                        Image(systemName: "fork.knife.circle.fill").font(.system(size: 39)).foregroundStyle(FitStyle.orange)
                    }.padding(.top, 10)
                    HStack {
                        Button { changeDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38) }
                        Spacer()
                        DatePicker("Log date", selection: $day, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.compact)
                        Spacer()
                        Button { changeDay(1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 38) }
                            .disabled(Calendar.current.isDateInToday(day))
                    }.font(.headline).buttonStyle(.plain).fitCard()
                    totals
                    HStack {
                        Text("QUICK ADD").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5)
                        Spacer()
                        Button { customOpen = true } label: {
                            Label("Custom food", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }.tint(FitStyle.orange)
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(FitStyle.muted)
                        TextField("Search saved food examples", text: $search)
                            .autocorrectionDisabled()
                    }.padding(13).modifier(LiquidPanel(corner: 14))
                    ForEach(foods) { food in
                        Button { selectedFood = food } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus").font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.black)
                                    .frame(width: 34, height: 34)
                                    .background(FitStyle.mint, in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(food.description).font(.caption).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(Int(food.calories)) kcal").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                    Text("\(Int(food.protein))g protein").font(.caption2).foregroundStyle(FitStyle.muted)
                                }
                            }.padding(13).modifier(LiquidPanel(corner: 16))
                        }.buttonStyle(.plain)
                    }
                    if foods.isEmpty { Text("No matching examples. Add a custom food above.").font(.caption).foregroundStyle(FitStyle.muted) }
                    HStack {
                        Text("TODAY'S LOG").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5)
                        Spacer()
                        Text("\(fit.meals(on: day).count) entries").font(.caption).foregroundStyle(FitStyle.muted)
                    }.padding(.top, 10)
                    if fit.meals(on: day).isEmpty {
                        Text("No meals logged for this day. Tap a food above to begin.")
                            .font(.subheadline).foregroundStyle(FitStyle.muted).fitCard()
                    } else {
                        ForEach(fit.meals(on: day).reversed()) { meal in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name).font(.subheadline.weight(.semibold))
                                    Text("P \(Int(meal.protein))  ·  C \(Int(meal.carbs))  ·  F \(Int(meal.fat))")
                                        .font(.caption2).foregroundStyle(FitStyle.muted)
                                }
                                Spacer()
                                Text("\(Int(meal.calories)) kcal").font(.subheadline.weight(.bold))
                                Button(role: .destructive) { fit.meals.removeAll { $0.id == meal.id } } label: {
                                    Image(systemName: "trash").foregroundStyle(FitStyle.muted).padding(.leading, 5)
                                }.accessibilityLabel("Delete \(meal.name)")
                            }.fitCard()
                        }
                    }
                    Text("Food values are estimates. Check your product labels and weighed portions for accuracy.")
                        .font(.caption2).foregroundStyle(FitStyle.muted).padding(.bottom, 8)
                }.padding(18)
            }
            .background(DeepBlueBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedFood) { item in
                QuickFoodSheet(food: item, day: day) { entry in fit.add(entry, on: day) }
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $customOpen) {
                CustomFoodSheet(day: day) { entry in fit.add(entry, on: day) }
            }
        }
    }

    private func changeDay(_ amount: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: amount, to: day), next <= Date() { day = next }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(fit.kcal(on: day)))").font(.system(size: 39, weight: .bold, design: .rounded))
                Text("/ \(fit.goals.calories) kcal").font(.subheadline).foregroundStyle(FitStyle.muted)
                Spacer()
                Image(systemName: "flame.fill").foregroundStyle(FitStyle.orange).font(.title2)
            }
            ProgressStripe(value: fit.kcal(on: day), goal: Double(fit.goals.calories), color: FitStyle.orange)
            HStack(spacing: 14) {
                macro("Protein", current: fit.protein(on: day), target: fit.goals.protein, color: FitStyle.mint)
                macro("Carbs", current: fit.carbs(on: day), target: fit.goals.carbs, color: FitStyle.blue)
                macro("Fat", current: fit.fat(on: day), target: fit.goals.fat, color: FitStyle.orange)
            }
        }.fitCard()
    }
    private func macro(_ label: String, current: Double, target: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(FitStyle.muted)
            Text("\(Int(current))/\(target) g").font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            ProgressStripe(value: current, goal: Double(target), color: color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuickFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: QuickFood
    let day: Date
    let onAdd: (FoodEntry) -> Void
    @State private var multiplier = 1.0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Headline(label: food.name, detail: food.description)
                HStack {
                    Text("Servings").font(.headline)
                    Spacer()
                    Button { multiplier = max(0.5, multiplier - 0.5) } label: { Image(systemName: "minus.circle.fill").font(.title) }
                    Text(multiplier.formatted(.number.precision(.fractionLength(0...1)))).font(.title2.bold()).frame(width: 46)
                    Button { multiplier = min(20, multiplier + 0.5) } label: { Image(systemName: "plus.circle.fill").font(.title) }
                }.tint(FitStyle.mint)
                HStack {
                    stat("CALORIES", "\(Int(food.calories * multiplier))")
                    stat("PROTEIN", "\(Int(food.protein * multiplier))g")
                    stat("CARBS", "\(Int(food.carbs * multiplier))g")
                    stat("FAT", "\(Int(food.fat * multiplier))g")
                }.fitCard()
                Button {
                    onAdd(food.makeEntry(multiplier: multiplier))
                    dismiss()
                } label: {
                    Text("Add to food log").font(.headline).frame(maxWidth: .infinity)
                        .padding(16).background(FitStyle.orange, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }
                Spacer()
            }.padding(20).background(FitStyle.bg)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallLabel(text: label)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let onAdd: (FoodEntry) -> Void
    @State private var name = ""
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Food name") {
                    TextField("e.g. Chicken dinner", text: $name)
                }
                Section("Nutrition for your portion") {
                    number("Calories (kcal)", value: $kcal)
                    number("Protein (g)", value: $protein)
                    number("Carbs (g)", value: $carbs)
                    number("Fat (g)", value: $fat)
                }
                Section {
                    Button("Save food entry") {
                        onAdd(FoodEntry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), calories: max(0, kcal), protein: max(0, protein), carbs: max(0, carbs), fat: max(0, fat)))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundStyle(FitStyle.orange)
                }
            }
            .scrollContentBackground(.hidden).background(FitStyle.bg)
            .navigationTitle("Custom food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
    }
}
