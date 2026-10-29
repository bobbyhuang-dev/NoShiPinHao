import SwiftUI

nonisolated enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case library

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "首页"
        case .library: "资料库"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        }
    }
}
