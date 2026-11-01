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

    /// The windows on screen, which captures look up WeChat's windows in. Fetch it once per scan.
    static func screenContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    /// Captures the title bar strip of a browser window, which holds its tab label.
    static func tabStrip(of window: WeChatWindow, pid: pid_t, in content: SCShareableContent) async throws
        -> Capture?
    {
        let size = CGSize(width: window.frame.width, height: ChannelsDetector.tabStripHeight)
        return try await capture(window, pid: pid, size: size, in: content)
    }

    /// Reads the text in a capture, such as a browser window's tab label.
    static func text(in capture: Capture) async throws -> [String] {
        try await recognizeText(in: capture).map(\.text)
    }

    /// Finds the Channels row in the main window's Discover list, if Channels is selected there.
    static func selectedChannelsRow(in window: WeChatWindow, pid: pid_t, content: SCShareableContent) async throws
        -> ChannelsDetector.DiscoverRows?
    {
        let size = CGSize(
            width: min(window.frame.width, ChannelsDetector.discoverListRegion.width),
            height: min(window.frame.height, ChannelsDetector.discoverListRegion.height)
        )
        guard let capture = try await capture(window, pid: pid, size: size, in: content),
            let rows = ChannelsDetector.discoverRows(in: try await recognizeText(in: capture))
        else { return nil }
        let image = capture.image

        // Compare the backgrounds just right of each label, where a row has no text or icons.
        let scale = CGFloat(image.width) / size.width
        func background(of row: CGRect) -> RGB? {
            image.averageColor(in: CGRect(x: row.maxX + 8, y: row.midY - 3, width: 20, height: 6), scale: scale)
        }
        guard let channels = background(of: rows.channels),
            ChannelsDetector.isHighlighted(row: channels, comparedTo: rows.references.compactMap(background))
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
    private static func capture(_ window: WeChatWindow, pid: pid_t, size: CGSize, in content: SCShareableContent)
        async throws -> Capture?
    {
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
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(window: scWindow.windowID, size: size, image: image)
    }
}

// MARK: - Text recognition

extension WeChatWindows {
    /// When text was last recognized, so the loop knows when the recognizer may have gone cold.
    private(set) static var lastRecognition = Date.distantPast

    /// Text read from each window's last capture, reused while the window looks the same.
    private static var recognized: [CGWindowID: (size: CGSize, pixels: Data, lines: [ChannelsDetector.TextLine])] =
        [:]

    /// Loads the text recognizer's models.
    ///
    /// The first recognition after the system has unloaded them takes 10 seconds or more, while later ones take a
    /// fraction of a second. Warming up ahead of time keeps that delay out of the first block.
    static func warmUpTextRecognition() async {
        let size = CGSize(width: 240, height: 60)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let label = ChannelsDetector.channelsLabels[0] as NSString
            label.draw(at: CGPoint(x: 12, y: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
            return true
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        lastRecognition = .now
        _ = try? await textRequest.perform(on: cgImage)
        lastRecognition = .now
    }

    private static var textRequest: RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
        return request
    }

    /// Whether a capture looks the same as its window's last one, so its text is known without recognizing it.
    static func hasKnownText(_ capture: Capture) -> Bool {
        guard let cached = recognized[capture.window], let pixels = capture.image.dataProvider?.data as Data?
        else { return false }
        return cached.size == capture.size && cached.pixels == pixels
    }

    /// Recognizes text in a capture, with frames in points from its top-left corner.
    ///
    /// Recognition is the slowest step of a scan, so a window that hasn't changed since its last capture reuses
    /// that capture's text.
    private static func recognizeText(in capture: Capture) async throws -> [ChannelsDetector.TextLine] {
        let pixels = capture.image.dataProvider?.data as Data?
        if let pixels, let cached = recognized[capture.window], cached.size == capture.size, cached.pixels == pixels {
            return cached.lines
        }
        let lines = try await textRequest.perform(on: capture.image).compactMap {
            observation -> ChannelsDetector.TextLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return .init(
                text: text, frame: observation.boundingBox.toImageCoordinates(capture.size, origin: .upperLeft))
        }
        lastRecognition = .now
        if let pixels {
            if recognized.count > 16 { recognized.removeAll() }
            recognized[capture.window] = (capture.size, pixels, lines)
        }
        return lines
    }
}

/// The top-left part of a window, captured as an image.
struct Capture {
    let window: CGWindowID
    /// Size in points of the captured region.
    let size: CGSize
    let image: CGImage
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
