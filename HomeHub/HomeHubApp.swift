import SwiftUI
import UIKit

@main
struct HomeHubApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var board = BoardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(board)
                .preferredColorScheme(.dark)
                .onAppear {
                    // A wall hub should never sleep while it is plugged in.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
