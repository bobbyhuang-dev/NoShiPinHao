import SwiftUI

@main
struct NoShiPinHaoApp: App {
    @State private var blocker = ChannelsBlocker()

    var body: some Scene {
        Window("去除视频号", id: "main") {
            ContentView(blocker: blocker)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                Link("去除视频号帮助", destination: URL(string: "https://github.com/bobbyhuang-dev/NoShiPinHao#readme")!)
            }
        }

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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("拦截视频号", isOn: $blocker.isEnabled)
        Text("已拦截 \(blocker.blockedCount) 次")
        switch blocker.status {
        case .needsPermissions:
            Button("授予权限…", action: showMainWindow)
        case .waitingForWeChat:
            Text("正在等待微信打开")
        case .blocking, .paused:
            EmptyView()
        }
        Divider()
        Button("打开去除视频号", action: showMainWindow)
        // 从菜单栏打开的窗口不会自动置于前台，所以先激活应用。
        Button("设置…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("退出去除视频号") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        NSApp.activate()
        openWindow(id: "main")
    }
}
