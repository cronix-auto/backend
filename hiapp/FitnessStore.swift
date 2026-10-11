import SwiftUI
import Foundation

struct FoodRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct LiftRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var exercise: String
    var kg: Double
    var reps: Int
}

struct WorkoutRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var name: String
    var minutes: Int
    var sets: Int
}

struct WeightRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var kg: Double
}

struct FoodPreset: Identifiable {
    let name: String
    let portion: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    var id: String { name }
    static let all: [FoodPreset] = [
        .init(name: "Chicken breast", portion: "100 g cooked", calories: 165, protein: 31, carbs: 0, fat: 3.6),
        .init(name: "Whole eggs", portion: "2 large eggs", calories: 144, protein: 12.6, carbs: 0.8, fat: 9.6),
        .init(name: "Greek yogurt", portion: "100 g, plain", calories: 97, protein: 9, carbs: 3.6, fat: 5),
        .init(name: "Potatoes", portion: "100 g cooked", calories: 87, protein: 1.9, carbs: 20, fat: 0.1),
        .init(name: "Protein milk", portion: "1 bottle, example", calories: 283, protein: 30, carbs: 40.6, fat: 0),
        .init(name: "Whey protein", portion: "1 scoop, typical", calories: 120, protein: 24, carbs: 3, fat: 1.5),
        .init(name: "Banana", portion: "1 medium", calories: 105, protein: 1.3, carbs: 27, fat: 0.4),
        .init(name: "Whole wheat bread", portion: "1 slice", calories: 80, protein: 4, carbs: 14, fat: 1),
        .init(name: "Olive oil", portion: "1 tablespoon", calories: 119, protein: 0, carbs: 0, fat: 13.5),
        .init(name: "Salad vegetables", portion: "200 g mixed", calories: 50, protein: 2, carbs: 10, fat: 0.3)
    ]
}

struct WorkoutPreset: Identifiable {
    let name: String
    let symbol: String
    let subtitle: String
    let exercises: [String]
    var id: String { name }
    static let all: [WorkoutPreset] = [
        .init(name: "Push", symbol: "figure.strengthtraining.traditional", subtitle: "Chest · shoulders · triceps", exercises: ["Incline dumbbell press", "Chest press", "Lateral raise", "Shoulder press", "Triceps pushdown"]),
        .init(name: "Pull", symbol: "dumbbell.fill", subtitle: "Back · biceps · rear delts", exercises: ["Lat pulldown", "Seated cable row", "Rear delt fly", "Preacher curl", "Hammer curl"]),
        .init(name: "Legs", symbol: "figure.run", subtitle: "Quads · hamstrings · calves", exercises: ["Leg press", "Leg curl", "Leg extension", "Calf raise", "Walking lunge"]),
        .init(name: "Arms", symbol: "figure.boxing", subtitle: "Biceps · triceps", exercises: ["Preacher curl", "Incline curl", "Hammer curl", "Triceps pushdown", "Overhead extension"]),
        .init(name: "Cardio", symbol: "figure.walk", subtitle: "Incline walk · conditioning", exercises: ["Incline treadmill", "Stationary bike", "Walking"])
    ]
}

@MainActor final class FitnessStore: ObservableObject {
    @Published var foods: [FoodRecord] = [] { didSet { persist(foods, "fit.foods") } }
    @Published var lifts: [LiftRecord] = [] { didSet { persist(lifts, "fit.lifts") } }
    @Published var workouts: [WorkoutRecord] = [] { didSet { persist(workouts, "fit.workouts") } }
    @Published var weights: [WeightRecord] = [] { didSet { persist(weights, "fit.weights") } }
    @Published var waters: [String: Int] = [:] { didSet { persist(waters, "fit.waters") } }
    @Published var calorieGoal: Int = 2200 { didSet { UserDefaults.standard.set(calorieGoal, forKey: "fit.calGoal") } }
    @Published var proteinGoal: Int = 160 { didSet { UserDefaults.standard.set(proteinGoal, forKey: "fit.proGoal") } }
    @Published var waterGoal: Int = 3000 { didSet { UserDefaults.standard.set(waterGoal, forKey: "fit.waterGoal") } }
    @Published var targetWeight: Double = 85 { didSet { UserDefaults.standard.set(targetWeight, forKey: "fit.weightGoal") } }
    @Published var activeName: String? = nil
    @Published var activeSince: Date? = nil
    @Published var activeExercises: [String] = []

    init() {
        foods = Self.retrieve([FoodRecord].self, "fit.foods") ?? []
        lifts = Self.retrieve([LiftRecord].self, "fit.lifts") ?? []
        workouts = Self.retrieve([WorkoutRecord].self, "fit.workouts") ?? []
        weights = Self.retrieve([WeightRecord].self, "fit.weights") ?? []
        waters = Self.retrieve([String: Int].self, "fit.waters") ?? [:]
        let d = UserDefaults.standard
        if d.object(forKey: "fit.calGoal") != nil { calorieGoal = d.integer(forKey: "fit.calGoal") }
        if d.object(forKey: "fit.proGoal") != nil { proteinGoal = d.integer(forKey: "fit.proGoal") }
        if d.object(forKey: "fit.waterGoal") != nil { waterGoal = d.integer(forKey: "fit.waterGoal") }
        if d.object(forKey: "fit.weightGoal") != nil { targetWeight = d.double(forKey: "fit.weightGoal") }
    }

    private static func retrieve<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func persist<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func sameDay(_ d: Date, _ day: Date = Date()) -> Bool {
        Calendar.current.isDate(d, inSameDayAs: day)
    }
    func foodsOn(_ day: Date = Date()) -> [FoodRecord] { foods.filter { sameDay($0.date, day) } }
    func caloriesOn(_ day: Date = Date()) -> Double { foodsOn(day).reduce(0) { $0 + $1.calories } }
    func proteinOn(_ day: Date = Date()) -> Double { foodsOn(day).reduce(0) { $0 + $1.protein } }
    func carbsOn(_ day: Date = Date()) -> Double { foodsOn(day).reduce(0) { $0 + $1.carbs } }
    func fatOn(_ day: Date = Date()) -> Double { foodsOn(day).reduce(0) { $0 + $1.fat } }
    func addWater(_ amount: Int) {
        let key = Self.dayKey(Date())
        waters[key] = max(0, (waters[key] ?? 0) + amount)
    }
    func waterToday() -> Int { waters[Self.dayKey(Date())] ?? 0 }
    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    func start(_ preset: WorkoutPreset) {
        activeName = preset.name
        activeExercises = preset.exercises
        activeSince = Date()
    }
    func finish() -> WorkoutRecord? {
        guard let name = activeName, let started = activeSince else { return nil }
        let record = WorkoutRecord(name: name, minutes: max(1, Int(Date().timeIntervalSince(started) / 60)), sets: lifts.filter { $0.date >= started }.count)
        workouts.insert(record, at: 0)
        activeName = nil
        activeSince = nil
        activeExercises = []
        return record
    }
    func cancelWorkout() {
        activeName = nil; activeSince = nil; activeExercises = []
    }
    func setsToday() -> Int { lifts.filter { sameDay($0.date) }.count }
    func workoutsThisWeek() -> Int {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workouts.filter { $0.date >= start }.count
    }
    func lastSevenDays() -> [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date())) }
    }
}

enum FitStyle {
    static let bg = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let card = Color(red: 0.11, green: 0.125, blue: 0.14)
    static let card2 = Color(red: 0.15, green: 0.165, blue: 0.18)
    static let lime = Color(red: 0.75, green: 0.99, blue: 0.34)
    static let muted = Color(red: 0.60, green: 0.64, blue: 0.65)
    static let orange = Color(red: 1, green: 0.67, blue: 0.38)
}
