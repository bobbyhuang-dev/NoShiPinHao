import SwiftUI

@main
struct NoShiPinHaoApp: App {
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
