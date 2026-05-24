// @main entry. Sets up the SwiftData container, runs seeder once per launch,
// pre-warms haptic generators, injects ToastCenter.

import SwiftUI
import SwiftData

@main
struct OurFitnessApp: App {
    let container: ModelContainer
    @StateObject private var toasts = ToastCenter()

    init() {
        self.container = AppModelContainer.make()
        Seeder.seedAll(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environmentObject(toasts)
                .task { Haptics.prepare() }   // cut first-tap latency to ~0
        }
    }
}
