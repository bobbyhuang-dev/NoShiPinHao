import SwiftUI

@main
struct NoShiPinHaoApp: App {
    @State private var blocker = ChannelsBlocker()

    var body: some Scene {
        Window("去除视频号", id: "main") {
            ContentView(blocker: blocker)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("去除视频号", systemImage: blocker.status.systemImage) {
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
        Toggle("拦截视频号", isOn: $blocker.isEnabled)
        Text("已拦截 \(blocker.blockedCount) 次")
        Divider()
        Button("打开去除视频号…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        SettingsLink()
            .keyboardShortcut(",")
        Divider()
        Button("退出去除视频号") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
