import SwiftUI

@main
struct NoShiPingHaoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
