import SwiftUI

nonisolated enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case library

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        }
    }
}
