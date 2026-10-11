import SwiftUI
import HealthKit
import Charts

enum FitStyle {
    static let bg = Color(red: 0.055, green: 0.065, blue: 0.083)
    static let card = Color(red: 0.108, green: 0.122, blue: 0.150)
    static let line = Color.white.opacity(0.085)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let mint = Color(red: 0.40, green: 0.90, blue: 0.73)
    static let blue = Color(red: 0.39, green: 0.70, blue: 1.0)
    static let muted = Color(red: 0.62, green: 0.67, blue: 0.73)
}

struct FoodEntry: Codable, Identifiable {
    var id = UUID()
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var date = Date()
}

struct WaterEntry: Codable, Identifiable {
    var id = UUID()
    var amount: Int
    var date = Date()
}

struct WeightEntry: Codable, Identifiable {
    var id = UUID()
    var kg: Double
    var date = Date()
}

struct LiftSet: Codable, Identifiable {
    var id = UUID()
    var exercise: String
    var kg: Double
    var reps: Int
}

struct WorkoutEntry: Codable, Identifiable {
    var id = UUID()
    var name: String
    var date = Date()
    var minutes: Int
    var sets: [LiftSet]
}

struct DailyGoals: Codable {
    var calories = 2000
    var protein = 150
    var carbs = 190
    var fat = 65
    var water = 3000
    var steps = 8000
    var targetKg = 85.0
}

struct QuickFood: Identifiable {
    let name: String
    let description: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    var id: String { name }
    func makeEntry(multiplier: Double) -> FoodEntry {
        FoodEntry(name: multiplier == 1 ? name : "\(name) × \(multiplier.formatted(.number.precision(.fractionLength(0...1))))", calories: calories * multiplier, protein: protein * multiplier, carbs: carbs * multiplier, fat: fat * multiplier)
    }
}

enum FoodCatalog {
    static let foods = [
        QuickFood(name: "Chicken breast", description: "250 g cooked", calories: 413, protein: 78, carbs: 0, fat: 9),
        QuickFood(name: "Whole eggs", description: "3 large eggs", calories: 216, protein: 19, carbs: 1, fat: 15),
        QuickFood(name: "Greek yogurt", description: "170 g plain, nonfat", calories: 100, protein: 17, carbs: 6, fat: 0),
        QuickFood(name: "Whey protein", description: "1 scoop, typical", calories: 120, protein: 24, carbs: 3, fat: 1),
        QuickFood(name: "Whole wheat bread", description: "2 slices", calories: 160, protein: 8, carbs: 28, fat: 2),
        QuickFood(name: "Air-fried potato", description: "250 g, without oil", calories: 193, protein: 5, carbs: 44, fat: 0),
        QuickFood(name: "Olive oil", description: "1 tbsp", calories: 119, protein: 0, carbs: 0, fat: 13.5),
        QuickFood(name: "Protein milk", description: "30 g protein serving, sample", calories: 283, protein: 30, carbs: 41, fat: 2),
        QuickFood(name: "Cucumber", description: "100 g", calories: 15, protein: 0.7, carbs: 3.6, fat: 0.1),
        QuickFood(name: "Chicken thigh", description: "200 g cooked, skinless", calories: 418, protein: 52, carbs: 0, fat: 22),
        QuickFood(name: "Romaine salad", description: "Large bowl, no dressing", calories: 45, protein: 3, carbs: 9, fat: 0.5),
        QuickFood(name: "Whole wheat paratha", description: "1 medium, estimate", calories: 300, protein: 7, carbs: 40, fat: 12)
    ]
}

final class FitStore: ObservableObject {
    @Published var meals: [FoodEntry] { didSet { save(meals, key: "fit.meals") } }
    @Published var water: [WaterEntry] { didSet { save(water, key: "fit.water") } }
    @Published var weights: [WeightEntry] { didSet { save(weights, key: "fit.weights") } }
    @Published var workouts: [WorkoutEntry] { didSet { save(workouts, key: "fit.workouts") } }
    @Published var goals: DailyGoals { didSet { save(goals, key: "fit.goals") } }
    @Published var currentWorkout: String? { didSet { UserDefaults.standard.set(currentWorkout, forKey: "fit.activeName") } }
    @Published var startedAt: Date? { didSet { UserDefaults.standard.set(startedAt, forKey: "fit.startedAt") } }
    @Published var activeSets: [LiftSet] { didSet { save(activeSets, key: "fit.activeSets") } }

    init() {
        meals = Self.load("fit.meals", fallback: [])
        water = Self.load("fit.water", fallback: [])
        weights = Self.load("fit.weights", fallback: [])
        workouts = Self.load("fit.workouts", fallback: [])
        goals = Self.load("fit.goals", fallback: DailyGoals())
        activeSets = Self.load("fit.activeSets", fallback: [])
        currentWorkout = UserDefaults.standard.string(forKey: "fit.activeName")
        startedAt = UserDefaults.standard.object(forKey: "fit.startedAt") as? Date
    }

    private static func load<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
    func meals(on day: Date) -> [FoodEntry] { meals.filter { Calendar.current.isDate($0.date, inSameDayAs: day) } }
    func water(on day: Date) -> Int { water.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount } }
    func kcal(on day: Date) -> Double { meals(on: day).reduce(0) { $0 + $1.calories } }
    func protein(on day: Date) -> Double { meals(on: day).reduce(0) { $0 + $1.protein } }
    func carbs(on day: Date) -> Double { meals(on: day).reduce(0) { $0 + $1.carbs } }
    func fat(on day: Date) -> Double { meals(on: day).reduce(0) { $0 + $1.fat } }
    func add(_ entry: FoodEntry, on day: Date) {
        var e = entry
        e.date = day
        meals.append(e)
    }
    func begin(_ name: String) { currentWorkout = name; startedAt = Date(); activeSets = [] }
    func finish() {
        guard let name = currentWorkout else { return }
        let mins = max(1, Int(Date().timeIntervalSince(startedAt ?? Date()) / 60))
        workouts.insert(WorkoutEntry(name: name, minutes: mins, sets: activeSets), at: 0)
        currentWorkout = nil; startedAt = nil; activeSets = []
    }
    var lastWeight: Double? { weights.sorted { $0.date > $1.date }.first?.kg }
    var personalBest: LiftSet? { (workouts.flatMap { $0.sets } + activeSets).max { $0.kg < $1.kg } }
}

final class AppleHealth: ObservableObject {
    @Published var steps = 0
    @Published var activeCalories = 0
    @Published var distanceKm = 0.0
    @Published var latestWeightKg: Double?
    @Published var workoutCount = 0
    @Published var lastHeartRate: Int?
    @Published var message = "Not connected"
    @Published var hasRequested = UserDefaults.standard.bool(forKey: "fit.healthRequested")
    private let store = HKHealthStore()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func connect() {
        guard available else { message = "Apple Health unavailable on this device"; return }
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .distanceWalkingRunning, .bodyMass, .heartRate]
        var reading = Set<HKObjectType>()
        for id in quantities { if let type = HKObjectType.quantityType(forIdentifier: id) { reading.insert(type) } }
        reading.insert(HKObjectType.workoutType())
        store.requestAuthorization(toShare: [], read: reading) { _, error in
            DispatchQueue.main.async {
                if let error = error { self.message = error.localizedDescription; return }
                self.hasRequested = true
                UserDefaults.standard.set(true, forKey: "fit.healthRequested")
                self.message = "Access requested. Data depends on your Health permissions."
                self.refresh()
            }
        }
    }

    func refresh() {
        guard available && hasRequested else { return }
        querySum(.stepCount, unit: .count()) { self.steps = Int($0) }
        querySum(.activeEnergyBurned, unit: .kilocalorie()) { self.activeCalories = Int($0) }
        querySum(.distanceWalkingRunning, unit: .meter()) { self.distanceKm = $0 / 1000.0 }
        latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo)) { self.latestWeightKg = $0 }
        latestQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute())) { self.lastHeartRate = Int($0) }
        let week = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: week, end: Date())
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            DispatchQueue.main.async { self.workoutCount = samples?.count ?? 0 }
        }
        store.execute(query)
    }

    private func querySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, update: @escaping (Double) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async { update(value) }
        }
        store.execute(query)
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, update: @escaping (Double) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return }
        let order = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [order]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            DispatchQueue.main.async { update(sample.quantity.doubleValue(for: unit)) }
        }
        store.execute(query)
    }
}

extension View {
    func fitCard() -> some View {
        self.padding(16).background(FitStyle.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}
struct SmallLabel: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.8).foregroundStyle(FitStyle.muted) }
}
struct ProgressStripe: View {
    let value: Double
    let goal: Double
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule().fill(color).frame(width: proxy.size.width * CGFloat(min(1, max(0, value / max(1, goal)))))
            }
        }.frame(height: 7)
    }
}
struct Headline: View {
    let label: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SmallLabel(text: detail)
            Text(label).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
    }
}

struct RootTabs: View {
    @EnvironmentObject var fit: FitStore
    @EnvironmentObject var health: AppleHealth
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            DashboardView(selectedTab: $tab).tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }.tag(0)
            NutritionView().tabItem { Label("Food", systemImage: "fork.knife") }.tag(1)
            TrainingView().tabItem { Label("Train", systemImage: "dumbbell.fill") }.tag(2)
            ProgressView().tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .tint(FitStyle.orange)
        .preferredColorScheme(.dark)
        .onAppear { health.refresh() }
    }
}

@main
struct HiApp: App {
    @StateObject private var fit = FitStore()
    @StateObject private var health = AppleHealth()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environmentObject(fit)
                .environmentObject(health)
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .active { health.refresh() }
        }
    }
}
