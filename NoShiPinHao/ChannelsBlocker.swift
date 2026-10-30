import AppKit
import ApplicationServices
import Observation
import UserNotifications
import os

/// Watches WeChat and closes any window showing Channels.
@Observable
final class ChannelsBlocker {
    enum Status {
        case blocking, paused, needsPermissions, waitingForWeChat
    }

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            updateLoop()
        }
    }

    private(set) var hasAccessibilityAccess = false
    private(set) var hasScreenRecordingAccess = false
    private(set) var isWeChatRunning = false
    private(set) var blockedCount: Int {
        didSet { defaults.set(blockedCount, forKey: Keys.blockedCount) }
    }
    private(set) var lastBlocked: Date? {
        didSet { defaults.set(lastBlocked, forKey: Keys.lastBlocked) }
    }

    var status: Status {
        if !isEnabled { return .paused }
        if !hasAccessibilityAccess || !hasScreenRecordingAccess { return .needsPermissions }
        return isWeChatRunning ? .blocking : .waitingForWeChat
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastDiscoverClick = Date.distantPast
    @ObservationIgnored private let logger = Logger(subsystem: "NoShiPingHao", category: "Blocker")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.isEnabled: true, Keys.notifyOnBlock: true])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        blockedCount = defaults.integer(forKey: Keys.blockedCount)
        lastBlocked = defaults.object(forKey: Keys.lastBlocked) as? Date
        refreshPermissions()
        updateLoop()
    }

    func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityAccess = AXIsProcessTrustedWithOptions(options)
        if !hasAccessibilityAccess { openPrivacySettings("Privacy_Accessibility") }
    }

    func requestScreenRecordingAccess() {
        hasScreenRecordingAccess = CGRequestScreenCaptureAccess()
        if !hasScreenRecordingAccess { openPrivacySettings("Privacy_ScreenCapture") }
    }

    func refreshPermissions() {
        hasAccessibilityAccess = AXIsProcessTrusted()
        hasScreenRecordingAccess = CGPreflightScreenCaptureAccess()
    }

    private func updateLoop() {
        loop?.cancel()
        loop = nil
        guard isEnabled else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func scan() async {
        refreshPermissions()
        let weChat = WeChatWindows.runningWeChat()
        isWeChatRunning = weChat != nil
        guard let weChat, hasAccessibilityAccess, hasScreenRecordingAccess else { return }
        let pid = weChat.processIdentifier

        do {
            for window in WeChatWindows.browserWindows(of: weChat) {
                let text = try await WeChatWindows.tabStripText(of: window, pid: pid)
                guard ChannelsDetector.isChannelsTab(recognizedText: text), isEnabled else { continue }
                if window.close() {
                    recordBlock()
                } else {
                    logger.error("Found a Channels window but could not close it")
                }
            }

            // Discover → Channels shows inside the main window. Only check it while WeChat is in front: that's the
            // only time it can be seen, and the only time it's safe to click in it.
            guard NSWorkspace.shared.frontmostApplication == weChat, let window = WeChatWindows.mainWindow(of: weChat),
                let rows = try await WeChatWindows.selectedChannelsRow(in: window, pid: pid), isEnabled,
                Date.now.timeIntervalSince(lastDiscoverClick) > 2.5
            else { return }
            // Select another Discover item, so Discover stays usable and doesn't reopen on Channels.
            let target = CGPoint(
                x: window.frame.minX + rows.alternative.midX, y: window.frame.minY + rows.alternative.midY)
            if Mouse.click(at: target, inWindowOf: pid) {
                lastDiscoverClick = .now
                recordBlock()
            }
        } catch {
            logger.error("Could not read WeChat window: \(error.localizedDescription)")
        }
    }

    private func recordBlock() {
        blockedCount += 1
        lastBlocked = .now
        guard defaults.bool(forKey: Keys.notifyOnBlock) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Channels blocked")
        content.body = String(localized: "NoShiPingHao kept WeChat from showing Channels.")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func openPrivacySettings(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}

extension ChannelsBlocker {
    enum Keys {
        static let isEnabled = "isEnabled"
        static let notifyOnBlock = "notifyOnBlock"
        static let blockedCount = "blockedCount"
        static let lastBlocked = "lastBlocked"
    }
}
