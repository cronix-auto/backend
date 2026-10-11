import SwiftUI

struct FoodRequest: Identifiable {
    let id = UUID()
    var preset: FoodReference? = nil
    var existing: FoodEntry? = nil
}

struct FoodPage: View {
    @EnvironmentObject private var data: FitStore
    @State private var day = Date()
    @State private var search = ""
    @State private var request: FoodRequest?
    private var matches: [FoodReference] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? FoodLibrary.all : FoodLibrary.all.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.detail.localizedCaseInsensitiveContains(text)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHead(title: "Food", subtitle: "Track weighed portions. Edit nutrition from the label.")
                    HStack {
                        Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden().tint(Forge.paleBlue)
                        Spacer()
                        Button { moveDay(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(Calendar.current.isDateInToday(day))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.plain).surface()

                    HStack(spacing: 10) {
                        stat("\(Int(data.kcal(on: day).rounded()))", "kcal")
                        stat("\(Int(data.protein(on: day).rounded()))", "protein g")
                        stat("\(Int(data.carbs(on: day).rounded()))", "carbs g")
                        stat("\(Int(data.fat(on: day).rounded()))", "fat g")
                    }

                    HStack {
                        Text("Add food").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Button {
                            request = FoodRequest()
                        } label: {
                            Label("Manual entry", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Forge.paleBlue)
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Forge.muted)
                        TextField("Search common foods", text: $search)
                            .font(.system(size: 14)).autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }.padding(13)
                        .background(Forge.inset, in: RoundedRectangle(cornerRadius: 12))

                    if matches.isEmpty {
                        Text("No match. Use Manual entry to log any food.")
                            .font(.subheadline).foregroundStyle(Forge.muted).surface()
                    }
                    LazyVStack(spacing: 7) {
                        ForEach(matches) { food in
                            Button { request = FoodRequest(preset: food) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 33, height: 33)
                                        .foregroundStyle(Forge.paleBlue)
                                        .background(Forge.darkBlue, in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name).font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(food.detail).font(.system(size: 11))
                                            .foregroundStyle(Forge.muted)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(Int(food.kcal)) kcal")
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                        Text("per 100 g").font(.system(size: 10))
                                            .foregroundStyle(Forge.muted)
                                    }
                                }.padding(.horizontal, 13).padding(.vertical, 11)
                                    .background(Forge.panel, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Nutrition references are estimates per 100g. For packaged foods, enter the label values; for meat, match raw or cooked weight.")
                        .font(.system(size: 11)).foregroundStyle(Forge.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Logged meals").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Text("\(data.meals(on: day).count) entries")
                            .font(.system(size: 12)).foregroundStyle(Forge.muted)
                    }.padding(.top, 6)
                    if data.meals(on: day).isEmpty {
                        EmptyLog(icon: "list.bullet", title: "No food logged",
                                 detail: "Your entries appear here after you save them.")
                    }
                    ForEach(MealPeriod.allCases) { period in
                        let items = data.meals(on: day).filter { ($0.mealType ?? "Snack") == period.rawValue }
                            .sorted { $0.date > $1.date }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 11) {
                                TinyLabel(text: period.rawValue)
                                ForEach(items) { item in
                                    HStack(spacing: 12) {
                                        Button { request = FoodRequest(existing: item) } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name).font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(.white)
                                                Text(item.quantityGrams.map { "\($0.short) g" } ??
                                                     "Manual portion")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Forge.muted)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Text("\(Int(item.calories.rounded())) kcal")
                                            .font(.system(size: 12, weight: .semibold))
                                        Button(role: .destructive) {
                                            data.meals.removeAll { $0.id == item.id }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(Forge.muted)
                                        }.buttonStyle(.plain)
                                    }
                                    if item.id != items.last?.id {
                                        Rectangle().fill(Forge.line).frame(height: 0.5)
                                    }
                                }
                            }.surface()
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }.forgePage()
            .sheet(item: $request) { item in
                FoodEditor(request: item, date: day)
                    .environmentObject(data)
            }
        }
    }

    private func moveDay(_ offset: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: offset, to: day), d <= Date() else { return }
        day = d
    }
    private func stat(_ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(.system(size: 21, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundStyle(Forge.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).surface(12)
    }
}

struct FoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var data: FitStore

    let request: FoodRequest
    let date: Date
    @State private var foodName: String
    @State private var grams: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var period: MealPeriod
    @State private var manual: Bool

    init(request: FoodRequest, date: Date) {
        self.request = request
        self.date = date
        let entry = request.existing
        let preset = request.preset
        _foodName = State(initialValue: entry?.name ?? preset?.name ?? "")
        _grams = State(initialValue: (entry?.quantityGrams ?? preset?.suggestedGrams ?? 100).short)
        _calories = State(initialValue: (entry?.calories ?? 0).short)
        _protein = State(initialValue: (entry?.protein ?? 0).short)
        _carbs = State(initialValue: (entry?.carbs ?? 0).short)
        _fat = State(initialValue: (entry?.fat ?? 0).short)
        _period = State(initialValue: MealPeriod(rawValue: entry?.mealType ?? "") ?? .dinner)
        _manual = State(initialValue: preset == nil)
    }
    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
    private var preview: (Double, Double, Double, Double) {
        if !manual, let preset = request.preset {
            let factor = (number(grams) ?? 0) / 100
            return (preset.kcal * factor, preset.p * factor, preset.c * factor, preset.f * factor)
        }
        return (number(calories) ?? 0, number(protein) ?? 0, number(carbs) ?? 0, number(fat) ?? 0)
    }
    private var valid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (number(grams) ?? 0) > 0 && (number(grams) ?? 0) <= 10000 &&
        [preview.0, preview.1, preview.2, preview.3].allSatisfy { $0.isFinite && $0 >= 0 && $0 < 20000 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHead(title: request.existing == nil ? "Log food" : "Edit food",
                             subtitle: request.preset == nil ? "Enter values from the nutrition label." :
                                "Portion in grams. Cooked and raw weights differ.")
                    VStack(alignment: .leading, spacing: 12) {
                        TinyLabel(text: "Food")
                        TextField("Name", text: $foodName)
                            .font(.system(size: 16, weight: .medium))
                            .padding(14)
                            .background(Forge.inset, in: RoundedRectangle(cornerRadius: 11))
                        InsetField(label: "Portion", value: $grams, suffix: "g")
                        TinyLabel(text: "Meal")
                        Picker("Meal", selection: $period) {
                            ForEach(MealPeriod.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }.pickerStyle(.segmented)
                    }.surface()

                    if let preset = request.preset, !manual {
                        VStack(alignment: .leading, spacing: 12) {
                            TinyLabel(text: "Nutrition calculated by gram weight")
                            HStack {
                                Text("\(Int(preview.0.rounded())) kcal")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                Spacer()
                                Text("P \(preview.1.short)  C \(preview.2.short)  F \(preview.3.short)")
                                    .font(.system(size: 11)).foregroundStyle(Forge.muted)
                            }
                            Button("Override with label values") {
                                calories = preview.0.short
                                protein = preview.1.short
                                carbs = preview.2.short
                                fat = preview.3.short
                                manual = true
                            }.font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Forge.paleBlue)
                            Text(preset.detail).font(.caption2).foregroundStyle(Forge.muted)
                        }.surface()
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            TinyLabel(text: "Nutrition for this portion")
                            HStack(spacing: 12) {
                                InsetField(label: "Calories", value: $calories, suffix: "kcal")
                                InsetField(label: "Protein", value: $protein, suffix: "g")
                            }
                            HStack(spacing: 12) {
                                InsetField(label: "Carbs", value: $carbs, suffix: "g")
                                InsetField(label: "Fat", value: $fat, suffix: "g")
                            }
                            Text("Enter exact package values or a recipe total. Calories may differ from macro-derived estimates due to fiber and rounding.")
                                .font(.system(size: 11)).foregroundStyle(Forge.muted)
                        }.surface()
                    }
                    SolidAction(title: request.existing == nil ? "Add to food log" : "Save changes",
                                symbol: "checkmark", enabled: valid) { save() }
                }.padding(.horizontal, 18).padding(.bottom, 20)
            }.forgePage()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundStyle(Forge.paleBlue)
                }
            }
        }
    }
    private func save() {
        guard valid else { return }
        var new = FoodEntry(
            name: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: preview.0, protein: preview.1, carbs: preview.2, fat: preview.3,
            date: Calendar.current.isDateInToday(date) ? Date() : date,
            quantityGrams: number(grams), mealType: period.rawValue
        )
        if let existing = request.existing {
            new.id = existing.id
            new.date = existing.date
            if let i = data.meals.firstIndex(where: { $0.id == existing.id }) {
                data.meals[i] = new
            }
        } else { data.meals.append(new) }
        dismiss()
    }
}
