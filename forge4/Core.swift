import SwiftUI
import Foundation

struct FoodEntry: Identifiable, Codable {
    var id = UUID()
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var date = Date()
    var quantityGrams: Double? = nil
    var mealType: String? = nil
}
struct WaterEntry: Identifiable, Codable {
    var id = UUID()
    var amount: Int
    var date = Date()
}
struct WeightEntry: Identifiable, Codable {
    var id = UUID()
    var kg: Double
    var date = Date()
}
struct LiftSet: Identifiable, Codable {
    var id = UUID()
    var exercise: String
    var kg: Double
    var reps: Int
    var rir: Int? = nil
    var isWarmup: Bool? = nil
    var note: String? = nil
    var working: Bool { !(isWarmup ?? false) }
    var volume: Double { working ? kg * Double(reps) : 0 }
    var estimatedMax: Double { reps > 0 && reps <= 12 && kg > 0 ? kg * (1 + Double(reps) / 30) : 0 }
}
struct WorkoutEntry: Identifiable, Codable {
    var id = UUID()
    var name: String
    var date = Date()
    var minutes: Int
    var sets: [LiftSet]
    var notes: String? = nil
}
struct DailyGoals: Codable {
    var calories = 2200
    var protein = 160
    var carbs = 210
    var fat = 70
    var water = 3000
    var steps = 8000
    var targetKg = 85.0
    var restSeconds: Int? = nil
}

enum MealPeriod: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snack"
    var id: String { rawValue }
}

struct FoodReference: Identifiable {
    let name: String
    let detail: String
    let kcal: Double
    let p: Double
    let c: Double
    let f: Double
    let suggestedGrams: Double
    var id: String { name }
    func scaled(_ grams: Double, period: MealPeriod, date: Date) -> FoodEntry {
        let factor = grams / 100
        return FoodEntry(
            name: name, calories: kcal * factor, protein: p * factor,
            carbs: c * factor, fat: f * factor, date: date,
            quantityGrams: grams, mealType: period.rawValue
        )
    }
}

enum FoodLibrary {
    // Indicative per 100g data; brands, cooking methods and oil change nutrition.
    static let all: [FoodReference] = [
        .init(name: "Chicken breast, cooked", detail: "Skinless · cooked weight", kcal: 165, p: 31, c: 0, f: 3.6, suggestedGrams: 250),
        .init(name: "Chicken breast, raw", detail: "Skinless · raw weight", kcal: 120, p: 22.5, c: 0, f: 2.6, suggestedGrams: 250),
        .init(name: "Chicken thigh, cooked", detail: "Skinless · cooked weight", kcal: 209, p: 26, c: 0, f: 10.9, suggestedGrams: 200),
        .init(name: "Whole eggs", detail: "About 50g per large egg", kcal: 143, p: 12.6, c: 0.7, f: 9.5, suggestedGrams: 150),
        .init(name: "Egg whites", detail: "Cooked without oil", kcal: 52, p: 10.9, c: 0.7, f: 0.2, suggestedGrams: 150),
        .init(name: "Potatoes, cooked", detail: "Plain, without oil", kcal: 87, p: 1.9, c: 20.1, f: 0.1, suggestedGrams: 250),
        .init(name: "Plain Greek yogurt", detail: "Example: full-fat, check label", kcal: 97, p: 9, c: 3.6, f: 5, suggestedGrams: 150),
        .init(name: "Nonfat Greek yogurt", detail: "Plain, check label", kcal: 59, p: 10.3, c: 3.6, f: 0.4, suggestedGrams: 170),
        .init(name: "Whole wheat bread", detail: "Use package weight", kcal: 247, p: 13, c: 41, f: 4.2, suggestedGrams: 70),
        .init(name: "Olive oil", detail: "1 tbsp is about 13.5g", kcal: 884, p: 0, c: 0, f: 100, suggestedGrams: 13.5),
        .init(name: "Cucumber", detail: "Raw", kcal: 15, p: 0.7, c: 3.6, f: 0.1, suggestedGrams: 150),
        .init(name: "Tomato", detail: "Raw", kcal: 18, p: 0.9, c: 3.9, f: 0.2, suggestedGrams: 120),
        .init(name: "Romaine lettuce", detail: "Raw", kcal: 17, p: 1.2, c: 3.3, f: 0.3, suggestedGrams: 100),
        .init(name: "Banana", detail: "Edible portion", kcal: 89, p: 1.1, c: 22.8, f: 0.3, suggestedGrams: 120),
        .init(name: "Cooked oats", detail: "With water", kcal: 71, p: 2.5, c: 12, f: 1.5, suggestedGrams: 200),
        .init(name: "Milk, whole", detail: "About 100 ml per 103g", kcal: 61, p: 3.2, c: 4.8, f: 3.3, suggestedGrams: 250),
        .init(name: "Rice, cooked", detail: "Plain white rice", kcal: 130, p: 2.7, c: 28.2, f: 0.3, suggestedGrams: 150)
    ]
}

struct ExerciseReference: Identifiable {
    let name: String
    let muscle: String
    var id: String { name }
}
enum ExerciseLibrary {
    static let templates: [(String, [String])] = [
        ("Push", ["Incline DB press", "Chest press", "Shoulder press", "Lateral raise", "Triceps pushdown"]),
        ("Pull", ["Lat pulldown", "Seated cable row", "Rear delt fly", "Preacher curl", "Hammer curl"]),
        ("Legs", ["Leg press", "Romanian deadlift", "Leg curl", "Leg extension", "Calf raise"]),
        ("Arms", ["Preacher curl", "Incline DB curl", "Hammer curl", "Triceps pushdown", "Overhead triceps extension"]),
        ("Full body", ["Incline DB press", "Lat pulldown", "Leg press", "Lateral raise", "Preacher curl"]),
        ("Custom", [])
    ]
    static let all: [ExerciseReference] = [
        .init(name: "Incline DB press", muscle: "Chest"),
        .init(name: "Flat DB press", muscle: "Chest"),
        .init(name: "Barbell bench press", muscle: "Chest"),
        .init(name: "Chest press", muscle: "Chest"),
        .init(name: "Cable fly", muscle: "Chest"),
        .init(name: "Lat pulldown", muscle: "Back"),
        .init(name: "Pull-up", muscle: "Back"),
        .init(name: "Seated cable row", muscle: "Back"),
        .init(name: "Chest-supported row", muscle: "Back"),
        .init(name: "Barbell row", muscle: "Back"),
        .init(name: "Rear delt fly", muscle: "Shoulders"),
        .init(name: "Lateral raise", muscle: "Shoulders"),
        .init(name: "Shoulder press", muscle: "Shoulders"),
        .init(name: "Preacher curl", muscle: "Arms"),
        .init(name: "Incline DB curl", muscle: "Arms"),
        .init(name: "Hammer curl", muscle: "Arms"),
        .init(name: "Triceps pushdown", muscle: "Arms"),
        .init(name: "Overhead triceps extension", muscle: "Arms"),
        .init(name: "Squat", muscle: "Legs"),
        .init(name: "Leg press", muscle: "Legs"),
        .init(name: "Romanian deadlift", muscle: "Legs"),
        .init(name: "Leg curl", muscle: "Legs"),
        .init(name: "Leg extension", muscle: "Legs"),
        .init(name: "Calf raise", muscle: "Legs"),
        .init(name: "Walking lunge", muscle: "Legs"),
        .init(name: "Incline treadmill", muscle: "Cardio")
    ]
    static func muscle(_ name: String) -> String { all.first { $0.name == name }?.muscle ?? "Other" }
}

enum Disk {
    static let base: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Forge", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static func read<T: Decodable>(_ file: String, fallbackKey: String, fallback: T) -> T {
        if let data = try? Data(contentsOf: base.appendingPathComponent(file)),
           let result = try? JSONDecoder().decode(T.self, from: data) { return result }
        if let data = UserDefaults.standard.data(forKey: fallbackKey),
           let result = try? JSONDecoder().decode(T.self, from: data) { return result }
        return fallback
    }
    static func write<T: Encodable>(_ value: T, file: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: base.appendingPathComponent(file), options: .atomic)
    }
}

@MainActor final class FitStore: ObservableObject {
    @Published var meals: [FoodEntry] { didSet { Disk.write(meals, file: "meals.json") } }
    @Published var water: [WaterEntry] { didSet { Disk.write(water, file: "water.json") } }
    @Published var weights: [WeightEntry] { didSet { Disk.write(weights, file: "weights.json") } }
    @Published var workouts: [WorkoutEntry] { didSet { Disk.write(workouts, file: "workouts.json") } }
    @Published var goals: DailyGoals { didSet { Disk.write(goals, file: "goals.json") } }
    @Published var currentWorkout: String? {
        didSet { UserDefaults.standard.set(currentWorkout, forKey: "fit.activeName") }
    }
    @Published var startedAt: Date? {
        didSet { UserDefaults.standard.set(startedAt, forKey: "fit.startedAt") }
    }
    @Published var activeSets: [LiftSet] {
        didSet { Disk.write(activeSets, file: "activeSets.json") }
    }
    @Published var activeNotes: String {
        didSet { UserDefaults.standard.set(activeNotes, forKey: "forge.activeNotes") }
    }
    init() {
        meals = Disk.read("meals.json", fallbackKey: "fit.meals", fallback: [])
        water = Disk.read("water.json", fallbackKey: "fit.water", fallback: [])
        weights = Disk.read("weights.json", fallbackKey: "fit.weights", fallback: [])
        workouts = Disk.read("workouts.json", fallbackKey: "fit.workouts", fallback: [])
        goals = Disk.read("goals.json", fallbackKey: "fit.goals", fallback: DailyGoals())
        activeSets = Disk.read("activeSets.json", fallbackKey: "fit.activeSets", fallback: [])
        currentWorkout = UserDefaults.standard.string(forKey: "fit.activeName")
        startedAt = UserDefaults.standard.object(forKey: "fit.startedAt") as? Date
        activeNotes = UserDefaults.standard.string(forKey: "forge.activeNotes") ?? ""
    }

    func meals(on date: Date) -> [FoodEntry] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    func water(on date: Date) -> Int {
        water.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.amount }
    }
    func kcal(on date: Date) -> Double { meals(on: date).reduce(0) { $0 + $1.calories } }
    func protein(on date: Date) -> Double { meals(on: date).reduce(0) { $0 + $1.protein } }
    func carbs(on date: Date) -> Double { meals(on: date).reduce(0) { $0 + $1.carbs } }
    func fat(on date: Date) -> Double { meals(on: date).reduce(0) { $0 + $1.fat } }
    var lastWeight: Double? { weights.max { $0.date < $1.date }?.kg }
    var workingSets: [LiftSet] { activeSets.filter(\.working) }
    func begin(_ name: String) {
        currentWorkout = name
        startedAt = Date()
        activeSets = []
        activeNotes = ""
    }
    func finish() {
        guard let name = currentWorkout else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(startedAt ?? Date()) / 60))
        workouts.insert(WorkoutEntry(name: name, minutes: minutes, sets: activeSets,
                                     notes: activeNotes.isEmpty ? nil : activeNotes), at: 0)
        clearSession()
    }
    func clearSession() { currentWorkout = nil; startedAt = nil; activeSets = []; activeNotes = "" }
    func previousSets(for exercise: String) -> [LiftSet] {
        workouts.sorted { $0.date > $1.date }
            .first { $0.sets.contains { $0.exercise == exercise } }?
            .sets.filter { $0.exercise == exercise } ?? []
    }
    func bestSet(for exercise: String) -> LiftSet? {
        workouts.flatMap(\.sets).filter { $0.exercise == exercise && $0.working }
            .max { $0.estimatedMax < $1.estimatedMax }
    }
    func weekCount() -> Int {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workouts.filter { $0.date >= start }.count
    }
    func weeklyMuscleSets() -> [(String, Int)] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let sets = workouts.filter { $0.date >= start }.flatMap(\.sets).filter(\.working)
        return ["Chest", "Back", "Shoulders", "Arms", "Legs"].map { muscle in
            (muscle, sets.filter { ExerciseLibrary.muscle($0.exercise) == muscle }.count)
        }
    }
}
