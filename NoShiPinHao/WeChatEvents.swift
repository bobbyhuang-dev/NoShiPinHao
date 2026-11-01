import AppKit
import ApplicationServices

/// Calls back when WeChat opens a window, changes focus or retitles something, so a scan can run right away instead
/// of waiting for the next tick.
final class WeChatEvents {
    let pid: pid_t
    private let observer: AXObserver
    private let onEvent: () -> Void

    private static let notifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXFocusedUIElementChangedNotification, kAXSelectedChildrenChangedNotification, kAXTitleChangedNotification,
        kAXApplicationActivatedNotification,
    ]

    init?(pid: pid_t, onEvent: @escaping () -> Void) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let events = Unmanaged<WeChatEvents>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { events.onEvent() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        self.pid = pid
        self.observer = observer
        self.onEvent = onEvent

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            AXObserverAddNotification(observer, app, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    isolated deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// Wakes a waiting loop early. A signal sent while nothing waits wakes the next wait at once.
final class ScanRequests {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isPending = false
    private var generation = 0

    func signal() {
        if continuation != nil { resume() } else { isPending = true }
    }

    /// Returns on the next signal, or after `timeout` if none comes.
    func wait(upTo timeout: Duration) async {
        if isPending {
            isPending = false
            return
        }
        generation += 1
        let generation = generation
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if self?.generation == generation { self?.resume() }
        }
        await withCheckedContinuation { continuation = $0 }
        timer.cancel()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

/// An opaque panel laid over a WeChat window, so the window can't be seen while its contents are checked.
final class Cover {
    private let panel: NSPanel

    /// Covers a window with `frame` in Accessibility coordinates, whose window number is `windowID`.
    init?(over frame: CGRect, windowID: CGWindowID) {
        // Accessibility frames are measured from the top of the primary screen, AppKit's from its bottom.
        guard let primary = NSScreen.screens.first else { return nil }
        let rect = CGRect(
            x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        panel = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.cornerRadius = 10
        panel.contentView = view
        // Just above WeChat's window, so it doesn't cover other apps' windows that are in front.
        panel.order(.above, relativeTo: Int(windowID))
    }

    /// Takes the cover away, after `delay` so a window that's closing has time to disappear first.
    func remove(after delay: Duration = .zero) {
        let panel = panel
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            panel.orderOut(nil)
        }
    }
}
