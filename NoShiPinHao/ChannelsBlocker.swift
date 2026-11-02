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
    @ObservationIgnored private var warmUp: Task<Void, Never>?
    @ObservationIgnored private var lastDiscoverClick = Date.distantPast
    @ObservationIgnored private let scanRequests = ScanRequests()
    @ObservationIgnored private var weChatEvents: WeChatEvents?
    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private var clicks: Any?
    /// 用户在微信中最近一次按下鼠标的位置（全局坐标，原点在主屏幕左上角）。
    @ObservationIgnored private var lastClick: CGPoint?
    /// 在此之前加快扫描，好在微信重绘后立刻看到点击的结果。
    @ObservationIgnored private var fastScanUntil = Date.distantPast
    /// Browser windows seen in the last scan, so new ones are covered before they are first read.
    @ObservationIgnored private var seenBrowserWindows: Set<CGWindowID> = []
    @ObservationIgnored private let logger = Logger(subsystem: "NoShiPinHao", category: "Blocker")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.isEnabled: true, Keys.notifyOnBlock: true])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        blockedCount = defaults.integer(forKey: Keys.blockedCount)
        lastBlocked = defaults.object(forKey: Keys.lastBlocked) as? Date
        refreshPermissions()
        // 通知默认开启，所以启动时就请求授权，否则在用户打开设置前通知都发不出去。
        if defaults.bool(forKey: Keys.notifyOnBlock) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [scanRequests] _ in
            MainActor.assumeIsolated { scanRequests.signal() }
        }
        // 点击“发现”中的视频号不会发出辅助功能通知，所以直接监听鼠标，点击后马上扫描。
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let location = event.cgEvent?.location
            MainActor.assumeIsolated { self?.weChatClicked(event.type, at: location) }
        }
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
        guard isEnabled else {
            weChatEvents = nil
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await scan()
                // Scan again at the next change in WeChat, or after a while, as not every change sends an event.
                await scanRequests.wait(upTo: Date.now < fastScanUntil ? Self.fastScanInterval : Self.scanInterval)
            }
        }
    }

    private func scan() async {
        refreshPermissions()
        let weChat = WeChatWindows.runningWeChat()
        isWeChatRunning = weChat != nil
        guard let weChat, hasAccessibilityAccess, hasScreenRecordingAccess else { return }
        let pid = weChat.processIdentifier
        if weChatEvents?.pid != pid {
            weChatEvents = WeChatEvents(pid: pid) { [scanRequests] in scanRequests.signal() }
        }
        keepTextRecognitionWarm()

        do {
            let content = try await WeChatWindows.screenContent()
            var browserWindows: Set<CGWindowID> = []
            defer { seenBrowserWindows = browserWindows }
            for window in WeChatWindows.browserWindows(of: weChat) {
                guard let tabStrip = try await WeChatWindows.tabStrip(of: window, pid: pid, in: content) else {
                    continue
                }
                browserWindows.insert(tabStrip.window)
                let cover = cover(window, while: tabStrip)
                let text = try await WeChatWindows.text(in: tabStrip)
                guard ChannelsDetector.isChannelsTab(recognizedText: text), isEnabled else {
                    cover?.remove()
                    continue
                }
                if window.close() {
                    cover?.remove(after: .milliseconds(400))
                    recordBlock()
                } else {
                    cover?.remove()
                    logger.error("Found a Channels window but could not close it")
                }
            }

            // Discover → Channels shows inside the main window. Only check it while WeChat is in front: that's the
            // only time it can be seen, and the only time it's safe to click in it.
            guard NSWorkspace.shared.frontmostApplication == weChat, let window = WeChatWindows.mainWindow(of: weChat),
                let rows = try await WeChatWindows.selectedChannelsRow(
                    in: window, pid: pid, content: content, lastClick: lastClick),
                isEnabled,
                Date.now.timeIntervalSince(lastDiscoverClick) > Self.discoverClickCooldown
            else { return }
            // Select another Discover item, so Discover stays usable and doesn't reopen on Channels.
            let target = CGPoint(
                x: window.frame.minX + rows.alternative.midX, y: window.frame.minY + rows.alternative.midY)
            if Mouse.click(at: target, inWindowOf: pid) {
                lastDiscoverClick = .now
                // 指针被移回视频号一行上，只是悬停，不能再当作选中。
                lastClick = nil
                recordBlock()
            }
        } catch {
            logger.error("Could not read WeChat window: \(error.localizedDescription)")
        }
    }

    private func weChatClicked(_ type: NSEvent.EventType, at location: CGPoint?) {
        guard isEnabled,
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ChannelsDetector.weChatBundleIdentifier
        else { return }
        if type == .leftMouseDown { lastClick = location ?? Mouse.location }
        fastScanUntil = .now + Self.fastScanDuration
        scanRequests.signal()
    }

    /// Covers a browser window while its changed tab strip is read, so Channels can't be seen while that runs.
    ///
    /// A window whose tab strip changes under the pointer is left uncovered unless it's new, as hovering over tabs
    /// changes their look, and covering the window each time would make it flicker.
    private func cover(_ window: WeChatWindow, while tabStrip: Capture) -> Cover? {
        guard !WeChatWindows.hasKnownText(tabStrip) else { return nil }
        let isNew = !seenBrowserWindows.contains(tabStrip.window)
        let strip = CGRect(
            x: window.frame.minX, y: window.frame.minY, width: window.frame.width,
            height: ChannelsDetector.tabStripHeight)
        guard isNew || !strip.contains(Mouse.location) else { return nil }
        return Cover(over: window.frame, windowID: tabStrip.window)
    }

    /// Warms up text recognition when it hasn't run for a while, so the system hasn't unloaded it by the time
    /// Channels opens. Otherwise the first block can take 10 seconds or more.
    private func keepTextRecognitionWarm() {
        guard warmUp == nil, Date.now.timeIntervalSince(WeChatWindows.lastRecognition) > Self.keepWarmInterval
        else { return }
        warmUp = Task { [weak self] in
            await WeChatWindows.warmUpTextRecognition()
            self?.warmUp = nil
        }
    }

    private func recordBlock() {
        blockedCount += 1
        lastBlocked = .now
        guard defaults.bool(forKey: Keys.notifyOnBlock) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "已拦截视频号")
        content.body = String(localized: "去除视频号阻止了微信显示视频号。")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func openPrivacySettings(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}

extension ChannelsBlocker {
    /// How often WeChat's windows are checked when no event comes sooner. Unchanged windows aren't read again, so
    /// checks are cheap.
    static let scanInterval = Duration.milliseconds(250)

    /// 在微信中点击后的一小段时间内，扫描的间隔。
    static let fastScanInterval = Duration.milliseconds(40)

    /// 点击后加快扫描多久。足够微信重绘，又不至于一直高频扫描。
    static let fastScanDuration: TimeInterval = 0.6

    /// 自动点开“发现”中的另一项后，至少隔多久才再点一次，以免微信还没重绘就重复点击。
    static let discoverClickCooldown: TimeInterval = 1

    /// How long text recognition may sit idle before it is warmed up again.
    static let keepWarmInterval: TimeInterval = 60

    enum Keys {
        static let isEnabled = "isEnabled"
        static let notifyOnBlock = "notifyOnBlock"
        static let blockedCount = "blockedCount"
        static let lastBlocked = "lastBlocked"
    }
}
