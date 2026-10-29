import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selection {
                DetailView(item: selection)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

private struct DetailView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(item.title)
                .font(.largeTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(item.title)
    }
}

#Preview {
    ContentView()
}
