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
                        Text("Block Channels")
                            .font(.headline)
                        Text(blocker.status.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Block Channels", isOn: $blocker.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
            }

            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets NoShiPingHao close Channels and switch WeChat away from it.",
                    isGranted: blocker.hasAccessibilityAccess,
                    request: blocker.requestAccessibilityAccess
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Lets NoShiPingHao see when WeChat is showing Channels.",
                    isGranted: blocker.hasScreenRecordingAccess,
                    request: blocker.requestScreenRecordingAccess
                )
            } header: {
                Text("Permissions")
            } footer: {
                Text(
                    "Nothing leaves your Mac. NoShiPingHao only looks at WeChat's title bar and Discover list, and reads them on-device."
                )
                .foregroundStyle(.secondary)
            }

            Section("Activity") {
                LabeledContent("WeChat", value: blocker.isWeChatRunning ? "Running" : "Not running")
                LabeledContent("Channels blocked", value: blocker.blockedCount, format: .number)
                LabeledContent("Last blocked") {
                    if let lastBlocked = blocker.lastBlocked {
                        Text(lastBlocked, format: .relative(presentation: .named))
                    } else {
                        Text("Never")
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
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access…", action: request)
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
        case .blocking: "On. WeChat Channels closes as soon as it opens."
        case .waitingForWeChat: "On. Waiting for WeChat to open."
        case .needsPermissions: "Grant the permissions below to start blocking."
        case .paused: "Off. Channels is not blocked."
        }
    }
}

#Preview {
    ContentView(blocker: ChannelsBlocker())
}
