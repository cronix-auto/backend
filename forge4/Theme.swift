import SwiftUI

enum Forge {
    static let black = Color.black
    static let panel = Color(red: 0.060, green: 0.069, blue: 0.091)
    static let inset = Color(red: 0.091, green: 0.105, blue: 0.138)
    static let blue = Color(red: 0.16, green: 0.40, blue: 0.89)
    static let darkBlue = Color(red: 0.085, green: 0.19, blue: 0.39)
    static let paleBlue = Color(red: 0.64, green: 0.79, blue: 1.0)
    static let muted = Color(red: 0.62, green: 0.65, blue: 0.72)
    static let line = Color.white.opacity(0.105)
    static let white = Color.white
}

struct Surface: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Forge.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Forge.line, lineWidth: 0.7))
    }
}
extension View {
    func surface(_ radius: CGFloat = 16) -> some View { modifier(Surface(radius: radius)) }
    func forgePage() -> some View {
        self.background(Forge.black).toolbar(.hidden, for: .navigationBar)
    }
}
struct TinyLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .default))
            .tracking(1.3).foregroundStyle(Forge.muted)
    }
}
struct PageHead: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 29, weight: .bold)).tracking(-0.8).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Forge.muted)
        }.padding(.top, 12).padding(.bottom, 6)
    }
}
struct Meter: View {
    let current: Double
    let target: Double
    var height: CGFloat = 7
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Forge.inset)
                Capsule().fill(Forge.blue)
                    .frame(width: g.size.width * CGFloat(min(1, max(0, current / max(target, 1)))))
            }
        }.frame(height: height)
    }
}
struct SolidAction: View {
    let title: String
    let symbol: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(enabled ? Forge.blue : Forge.inset,
                            in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!enabled)
    }
}
struct InsetField: View {
    let label: String
    @Binding var value: String
    var suffix = ""
    var decimal = true
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TinyLabel(text: label)
            HStack(spacing: 6) {
                TextField("0", text: $value)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(Forge.paleBlue)
                if !suffix.isEmpty {
                    Text(suffix).font(.caption).foregroundStyle(Forge.muted)
                }
            }
            .padding(.horizontal, 13).frame(height: 49)
            .background(Forge.inset, in: RoundedRectangle(cornerRadius: 11))
        }
    }
}
struct EmptyLog: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Forge.muted)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12))
                .foregroundStyle(Forge.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28).surface()
    }
}
extension Double {
    var short: String { formatted(.number.precision(.fractionLength(0...1))) }
}
extension Date {
    var dayTitle: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}
struct AppTabs: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            HomePage(selection: $selection)
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }.tag(0)
            FoodPage()
                .tabItem { Label("Food", systemImage: "fork.knife") }.tag(1)
            TrainPage()
                .tabItem { Label("Train", systemImage: "dumbbell") }.tag(2)
            ProgressPage()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(3)
            GoalsPage()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(4)
        }
        .tint(Forge.blue).preferredColorScheme(.dark)
    }
}

@main struct ForgeApp: App {
    @StateObject private var data = FitStore()
    var body: some Scene {
        WindowGroup {
            AppTabs().environmentObject(data)
        }
    }
}
