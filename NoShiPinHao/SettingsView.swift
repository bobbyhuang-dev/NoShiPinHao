import ServiceManagement
import SwiftUI
import UserNotifications

/// 只有一页设置，所以按照 macOS 惯例不显示标签栏。
struct SettingsView: View {
    @AppStorage(ChannelsBlocker.Keys.notifyOnBlock) private var notifyOnBlock = true
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("登录时打开", isOn: launchAtLogin)
                if loginItemStatus == .requiresApproval {
                    ApprovalNote(
                        message: "需要在“系统设置”中允许。",
                        buttonTitle: "打开登录项设置…",
                        action: SMAppService.openSystemSettingsLoginItems
                    )
                }
            }

            Section {
                Toggle("拦截视频号时发送通知", isOn: $notifyOnBlock)
                    .onChange(of: notifyOnBlock) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                            await refreshNotificationStatus()
                        }
                    }
                if notifyOnBlock && notificationsDenied {
                    ApprovalNote(
                        message: "通知已在“系统设置”中关闭。",
                        buttonTitle: "打开通知设置…",
                        action: openNotificationSettings
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = SMAppService.mainApp.status
            Task { await refreshNotificationStatus() }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginItemStatus == .enabled || loginItemStatus == .requiresApproval
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // 系统拒绝时，开关回到实际状态。
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    private func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!
        NSWorkspace.shared.open(url)
    }
}

/// 说明某项设置还需要在“系统设置”中处理，并提供打开它的按钮。
private struct ApprovalNote: View {
    let message: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        LabeledContent {
            Button(buttonTitle, action: action)
        } label: {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
