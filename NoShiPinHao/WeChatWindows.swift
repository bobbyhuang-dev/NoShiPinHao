import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// A WeChat window found through the Accessibility API.
struct WeChatWindow {
    let element: AXUIElement
    let frame: CGRect

    /// Presses the window's close button.
    @discardableResult
    func close() -> Bool {
        guard let button: AXUIElement = element.value(of: kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
}

enum WeChatWindows {
    static func runningWeChat() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: ChannelsDetector.weChatBundleIdentifier).first
    }

    /// WeChat's built-in browser windows, where Channels opens from a shared video.
    static func browserWindows(of app: NSRunningApplication) -> [WeChatWindow] {
        windows(of: app).filter { ChannelsDetector.isBrowserWindow(title: $0.title) }.map(\.window)
    }

    /// WeChat's main window, the largest window that isn't a browser window.
    static func mainWindow(of app: NSRunningApplication) -> WeChatWindow? {
        windows(of: app)
            .filter { !ChannelsDetector.isBrowserWindow(title: $0.title) }
            .max { $0.window.frame.width * $0.window.frame.height < $1.window.frame.width * $1.window.frame.height }?
            .window
    }

    /// Reads the tab label in a browser window's title bar.
    static func tabStripText(of window: WeChatWindow, pid: pid_t) async throws -> [String] {
        let size = CGSize(width: window.frame.width, height: ChannelsDetector.tabStripHeight)
        guard let image = try await capture(window, pid: pid, size: size) else { return [] }
        return try await recognizeText(in: image, size: size).map(\.text)
    }

    /// Finds the Channels row in the main window's Discover list, if Channels is selected there.
    static func selectedChannelsRow(in window: WeChatWindow, pid: pid_t) async throws -> ChannelsDetector.DiscoverRows?
    {
        let size = CGSize(
            width: min(window.frame.width, ChannelsDetector.discoverListRegion.width),
            height: min(window.frame.height, ChannelsDetector.discoverListRegion.height)
        )
        guard let image = try await capture(window, pid: pid, size: size),
            let rows = ChannelsDetector.discoverRows(in: try await recognizeText(in: image, size: size))
        else { return nil }

        // Compare the backgrounds just right of each label, where a row has no text or icons.
        let scale = CGFloat(image.width) / size.width
        func background(of row: CGRect) -> RGB? {
            image.averageColor(in: CGRect(x: row.maxX + 8, y: row.midY - 3, width: 20, height: 6), scale: scale)
        }
        guard let channels = background(of: rows.channels), let other = background(of: rows.alternative),
            ChannelsDetector.isHighlighted(row: channels, comparedTo: other)
        else { return nil }

        // A row the pointer hovers over is highlighted too.
        let channelsRow = rows.channels.offsetBy(dx: window.frame.minX, dy: window.frame.minY).insetBy(dx: -40, dy: -8)
        guard !channelsRow.contains(Mouse.location) else { return nil }
        return rows
    }

    private static func windows(of app: NSRunningApplication) -> [(title: String, window: WeChatWindow)] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows: [AXUIElement] = appElement.value(of: kAXWindowsAttribute) ?? []
        return windows.compactMap { window in
            guard let title: String = window.value(of: kAXTitleAttribute), let frame = window.frame else { return nil }
            return (title, WeChatWindow(element: window, frame: frame))
        }
    }

    /// Captures the top-left `size` points of a window.
    private static func capture(_ window: WeChatWindow, pid: pid_t, size: CGSize) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard
            let scWindow = content.windows.first(where: {
                $0.owningApplication?.processID == pid && $0.frame.isClose(to: window.frame)
            })
        else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(origin: .zero, size: size)
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Recognizes text in an image of `size` points, with frames in points from its top-left corner.
    private static func recognizeText(in image: CGImage, size: CGSize) async throws -> [ChannelsDetector.TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
        return try await request.perform(on: image).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return .init(text: text, frame: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft))
        }
    }
}

/// Clicks on behalf of the user, then puts the pointer back.
enum Mouse {
    static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Clicks `point` in global coordinates, but only if the topmost window there belongs to `pid` and no mouse
    /// button is held, so the click can't land in another app or interrupt a drag.
    @discardableResult
    static func click(at point: CGPoint, inWindowOf pid: pid_t) -> Bool {
        guard NSEvent.pressedMouseButtons == 0, topmostWindowOwner(at: point) == pid else { return false }
        let saved = location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(saved)
        return true
    }

    private static func topmostWindowOwner(at point: CGPoint) -> pid_t? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
        return windows.first { info in
            guard info[kCGWindowLayer] as? Int == 0, let bounds = info[kCGWindowBounds] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return rect.contains(point)
        }?[kCGWindowOwnerPID] as? pid_t
    }
}

extension AXUIElement {
    fileprivate func value<T>(of attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    fileprivate var frame: CGRect? {
        guard let position: AXValue = value(of: kAXPositionAttribute),
            let size: AXValue = value(of: kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

extension CGImage {
    /// The average color of a rect given in points, in an image with `scale` pixels per point.
    fileprivate func averageColor(in rect: CGRect, scale: CGFloat) -> RGB? {
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        )
        .integral
        guard let crop = cropping(to: pixels),
            let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return RGB(red: Int(data[0]), green: Int(data[1]), blue: Int(data[2]))
    }
}

extension CGRect {
    fileprivate func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
