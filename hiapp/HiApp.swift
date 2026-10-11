import SwiftUI

@main
struct HiApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hi")
                .font(.system(size: 48, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
