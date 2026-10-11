import SwiftUI

@main
struct HiApp: App {
    @StateObject private var data = FitnessStore()
    @StateObject private var health = HealthBridge()

    var body: some Scene {
        WindowGroup {
            FitnessShell()
                .environmentObject(data)
                .environmentObject(health)
                .preferredColorScheme(.dark)
        }
    }
}

struct FitnessShell: View {
    @EnvironmentObject private var health: HealthBridge
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayScreen(tab: $selection)
                .tabItem { Label("Today", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            FoodScreen()
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(1)
            TrainingScreen()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(2)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(3)
            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(FitStyle.lime)
        .toolbarBackground(FitStyle.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear { health.refreshIfConnected() }
        .onChange(of: selection) { newValue in
            if newValue == 0 { health.refreshIfConnected() }
        }
    }
}
