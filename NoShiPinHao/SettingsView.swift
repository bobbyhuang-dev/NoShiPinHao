import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") {
                GeneralSettingsView()
            }
        }
        .scenePadding()
        .frame(width: 420)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true

    var body: some View {
        Form {
            Toggle("启动时显示欢迎页", isOn: $showWelcomeOnLaunch)
        }
    }
}

#Preview {
    SettingsView()
}
