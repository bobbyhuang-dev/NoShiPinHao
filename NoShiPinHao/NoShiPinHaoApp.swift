import SwiftUI

@main
struct NoShiPinHaoApp: App {
    @State private var blocker = ChannelsBlocker()

    var body: some Scene {
        Window("NoShiPingHao", id: "main") {
            ContentView(blocker: blocker)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("NoShiPingHao", systemImage: blocker.status.systemImage) {
            MenuBarContent(blocker: blocker)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuBarContent: View {
    @Bindable var blocker: ChannelsBlocker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Block Channels", isOn: $blocker.isEnabled)
        Text("Blocked \(blocker.blockedCount) times")
        Divider()
        Button("Open NoShiPingHao…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink()
            .keyboardShortcut(",")
        Divider()
        Button("Quit NoShiPingHao") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
