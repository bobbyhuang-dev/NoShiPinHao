import Testing
@testable import NoShiPingHao

struct SidebarItemTests {
    @Test func everyItemHasASymbol() {
        for item in SidebarItem.allCases {
            #expect(!item.systemImage.isEmpty)
        }
    }

    @Test func idMatchesCase() {
        #expect(SidebarItem.home.id == .home)
    }
}
