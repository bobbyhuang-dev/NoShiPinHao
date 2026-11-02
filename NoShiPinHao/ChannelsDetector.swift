import CoreGraphics
import Foundation

/// Rules for recognizing WeChat Channels (视频号).
///
/// WeChat 4 shows Channels in two places:
/// - Its built-in browser window, when Channels is opened from a video a friend sent. That window's accessibility
///   title is a fixed placeholder, so the page is identified by the tab label drawn in its title bar.
/// - The main window, when Channels is selected in the Discover list. It is identified by the highlighted
///   "Channels" row under the "Discover" header.
nonisolated enum ChannelsDetector {
    static let weChatBundleIdentifier = "com.tencent.xinWeChat"

    /// Titles WeChatAppEx gives its browser windows, from its `locale.pak` files (en, zh_CN, zh_TW).
    static let browserWindowTitles: Set<String> = ["WeChat (Window)", "微信 (窗口)", "WeChat (視窗)"]

    /// Labels WeChat uses for Channels, by language.
    static let channelsLabels = ["视频号", "視頻號", "视频號", "Channels"]

    /// Headers of the Discover list, by language.
    static let discoverHeaders: Set<String> = ["Discover", "发现", "發現"]

    /// Height in points of the browser window's title bar strip that holds the tab label.
    static let tabStripHeight: CGFloat = 52

    /// Region of the main window, from its top-left corner, that holds the Discover list.
    static let discoverListRegion = CGSize(width: 360, height: 520)

    /// A line of recognized text, with its frame in points from the top-left of the captured region.
    struct TextLine: Equatable {
        var text: String
        var frame: CGRect
    }

    /// Rows of the Discover list worth looking at once Channels may be selected.
    struct DiscoverRows: Equatable {
        /// The Channels row.
        var channels: CGRect
        /// Another row in the list, to select instead of Channels.
        var alternative: CGRect
        /// The Discover header and the list's other rows, which Channels' background is compared against.
        var references: [CGRect]
        /// “发现”标题。它的像素没变，就说明列表还在原处，不必重新识别文字。
        var header: CGRect
    }

    static func isBrowserWindow(title: String) -> Bool {
        browserWindowTitles.contains(title.trimmingCharacters(in: .whitespaces))
    }

    /// Whether any line of text read from the browser tab strip names Channels.
    static func isChannelsTab(recognizedText lines: [String]) -> Bool {
        lines.contains { line in
            let compact = line.filter { !$0.isWhitespace }
            return channelsLabels.contains { compact.localizedCaseInsensitiveContains($0) }
        }
    }

    /// Finds the Channels row of the Discover list and another row in the same list.
    ///
    /// Returns `nil` unless the Discover header is visible, so a chat preview such as "[Channels]" never matches.
    static func discoverRows(in lines: [TextLine]) -> DiscoverRows? {
        guard let header = lines.first(where: { discoverHeaders.contains(compact($0.text)) }) else { return nil }
        let rows = lines.filter { $0.frame.minY > header.frame.maxY }
        guard let channels = rows.first(where: { isChannelsLabel($0.text) }) else { return nil }
        let others = rows.filter { $0 != channels && abs($0.frame.minX - channels.frame.minX) < 12 }
        guard let alternative = others.min(by: { $0.frame.minY < $1.frame.minY }) else { return nil }
        return DiscoverRows(
            channels: channels.frame, alternative: alternative.frame, references: [header.frame] + others.map(\.frame),
            header: header.frame)
    }

    /// Whether a row's background stands out from all the others', meaning it is selected.
    ///
    /// Standing out from a single row isn't enough: that row may be the selected or hovered one, as when Moments is
    /// open, and then it's the one that stands out.
    static func isHighlighted(row: RGB, comparedTo references: [RGB]) -> Bool {
        !references.isEmpty
            && references.allSatisfy { reference in
                max(abs(row.red - reference.red), abs(row.green - reference.green), abs(row.blue - reference.blue))
                    > 24
            }
    }

    /// 指针悬停的行也会高亮。所以指针停在视频号一行上时，只有用户最近一次按下鼠标也在这一行，高亮才算选中。
    static func highlightMeansSelected(row: CGRect, pointer: CGPoint, lastClick: CGPoint?) -> Bool {
        !row.contains(pointer) || lastClick.map(row.contains) == true
    }

    /// 两块同样大小的 RGBA 像素看起来是否相同。
    ///
    /// 允许少量像素不同，这样半透明窗口背后的内容变化不会让缓存失效；而换成另一段文字时，大部分笔画都会不同。
    static func looksSame(_ pixels: [UInt8], _ other: [UInt8]) -> Bool {
        guard pixels.count == other.count, pixels.count >= 4, pixels.count.isMultiple(of: 4) else { return false }
        var differing = 0
        for start in stride(from: 0, to: pixels.count, by: 4) {
            let isDifferent = (start..<start + 3).contains { abs(Int(pixels[$0]) - Int(other[$0])) > 32 }
            if isDifferent { differing += 1 }
        }
        // 最多 1% 的像素不同。
        return differing * 100 <= pixels.count / 4
    }

    /// A label is a Channels row when it reads as the label alone, allowing a misread icon or two before it.
    private static func isChannelsLabel(_ text: String) -> Bool {
        let text = compact(text)
        return channelsLabels.contains { text.hasSuffix($0) && text.count <= $0.count + 2 }
    }

    private static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }
}

/// An sRGB color with 0–255 components.
nonisolated struct RGB: Equatable {
    var red: Int
    var green: Int
    var blue: Int
}
