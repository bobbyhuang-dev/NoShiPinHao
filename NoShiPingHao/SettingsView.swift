import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
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
            Toggle("Show welcome on launch", isOn: $showWelcomeOnLaunch)
        }
    }
}

#Preview {
    SettingsView()
}
