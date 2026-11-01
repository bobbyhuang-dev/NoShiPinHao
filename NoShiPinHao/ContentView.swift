import SwiftUI

struct ContentView: View {
    @Bindable var blocker: ChannelsBlocker

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: blocker.status.systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(blocker.status.tint)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("拦截视频号")
                            .font(.headline)
                        Text(blocker.status.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("拦截视频号", isOn: $blocker.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
            }

            Section {
                PermissionRow(
                    title: "辅助功能",
                    detail: "用于关闭视频号，并让微信离开视频号页面。",
                    isGranted: blocker.hasAccessibilityAccess,
                    request: blocker.requestAccessibilityAccess
                )
                PermissionRow(
                    title: "屏幕录制",
                    detail: "用于发现微信何时在显示视频号。",
                    isGranted: blocker.hasScreenRecordingAccess,
                    request: blocker.requestScreenRecordingAccess
                )
            } header: {
                Text("权限")
            } footer: {
                Text(
                    "所有数据都不会离开你的 Mac。本工具只查看微信的标题栏和“发现”列表，并在本机识别文字。"
                )
                .foregroundStyle(.secondary)
            }

            Section("活动") {
                LabeledContent("微信", value: blocker.isWeChatRunning ? "正在运行" : "未运行")
                LabeledContent("已拦截次数", value: blocker.blockedCount, format: .number)
                LabeledContent("上次拦截") {
                    if let lastBlocked = blocker.lastBlocked {
                        Text(lastBlocked, format: .relative(presentation: .named))
                    } else {
                        Text("从未")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            blocker.refreshPermissions()
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("授权…", action: request)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

extension ChannelsBlocker.Status {
    var systemImage: String {
        switch self {
        case .blocking: "checkmark.shield.fill"
        case .waitingForWeChat: "shield.fill"
        case .needsPermissions: "exclamationmark.shield.fill"
        case .paused: "shield.slash"
        }
    }

    var tint: Color {
        switch self {
        case .blocking: .green
        case .waitingForWeChat: .accentColor
        case .needsPermissions: .orange
        case .paused: .secondary
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .blocking: "已开启。视频号一打开就会被关闭。"
        case .waitingForWeChat: "已开启。正在等待微信打开。"
        case .needsPermissions: "请授予下方权限以开始拦截。"
        case .paused: "已关闭。视频号不会被拦截。"
        }
    }
}

#Preview {
    ContentView(blocker: ChannelsBlocker())
}
