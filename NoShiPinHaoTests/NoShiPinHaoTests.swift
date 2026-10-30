import CoreGraphics
import Testing

@testable import NoShiPinHao

struct ChannelsDetectorTests {
    @Test(arguments: ["WeChat (Window)", "微信 (窗口)", "WeChat (視窗)"])
    func recognizesBrowserWindowTitles(title: String) {
        #expect(ChannelsDetector.isBrowserWindow(title: title))
    }

    @Test(arguments: ["Weixin", "微信", "肯德基自助点餐", ""])
    func ignoresOtherWindows(title: String) {
        #expect(!ChannelsDetector.isBrowserWindow(title: title))
    }

    @Test(arguments: [["•视频号"], ["4》 视频号"], ["视 频 号"], ["視頻號"], ["Channels"], ["Loading.....", "视频号"]])
    func recognizesChannelsTab(text: [String]) {
        #expect(ChannelsDetector.isChannelsTab(recognizedText: text))
    }

    @Test(arguments: [[], ["Loading....."], ["岁岁重阳，愿君安康！", "ASK AI"], ["视频"]])
    func ignoresOtherTabs(text: [String]) {
        #expect(!ChannelsDetector.isChannelsTab(recognizedText: text))
    }
}

struct DiscoverListTests {
    private func line(_ text: String, y: CGFloat, x: CGFloat = 72) -> ChannelsDetector.TextLine {
        .init(text: text, frame: CGRect(x: x, y: y, width: 60, height: 14))
    }

    private var discoverList: [ChannelsDetector.TextLine] {
        [
            line("Discover", y: 12, x: 64), line("Moments", y: 46), line("W Channels", y: 80), line("Search", y: 114),
            line("推荐", y: 14, x: 440),
        ]
    }

    @Test func findsChannelsAndTheFirstOtherRow() throws {
        let rows = try #require(ChannelsDetector.discoverRows(in: discoverList))
        #expect(rows.channels.minY == 80)
        #expect(rows.alternative.minY == 46)
    }

    @Test func findsChineseLabels() {
        let lines = [line("发现", y: 12, x: 64), line("朋友圈", y: 46), line("视频号", y: 80)]
        #expect(ChannelsDetector.discoverRows(in: lines)?.channels.minY == 80)
    }

    @Test func needsTheDiscoverHeader() {
        #expect(ChannelsDetector.discoverRows(in: Array(discoverList.dropFirst())) == nil)
    }

    @Test func ignoresChatPreviewsMentioningChannels() {
        let lines = [line("Discover", y: 12, x: 64), line("[Channels] 维秘机对哥", y: 46), line("Moments", y: 80)]
        #expect(ChannelsDetector.discoverRows(in: lines) == nil)
    }

    @Test func comparesRowBackgrounds() {
        let unselected = RGB(red: 61, green: 61, blue: 62)
        #expect(ChannelsDetector.isHighlighted(row: RGB(red: 95, green: 176, blue: 129), comparedTo: unselected))
        #expect(!ChannelsDetector.isHighlighted(row: RGB(red: 64, green: 64, blue: 64), comparedTo: unselected))
    }
}
