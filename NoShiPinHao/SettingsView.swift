import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
        }
        .scenePadding()
        .frame(width: 420)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(ChannelsBlocker.Keys.notifyOnBlock) private var notifyOnBlock = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Notify when Channels is blocked", isOn: $notifyOnBlock)
                .onChange(of: notifyOnBlock, initial: true) { _, enabled in
                    guard enabled else { return }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
                }
        }
    }
}

#Preview {
    SettingsView()
}
