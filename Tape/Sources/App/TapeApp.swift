import SwiftUI

@main
struct TapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement apps don't reliably show Settings scenes.
        // Settings window is managed manually via AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
