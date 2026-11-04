// App/RootView.swift

import SwiftUI

struct RootView: View {
    @State private var scanViewModel: ScanViewModel
    @State private var logViewModel: LogViewModel
    private let settingsViewModel: SettingsViewModel

    init(dependencies: AppDependencies) {
        _scanViewModel = State(initialValue: ScanViewModel(dependencies: dependencies))
        _logViewModel = State(initialValue: LogViewModel(persistence: dependencies.persistence))
        settingsViewModel = SettingsViewModel(dependencies: dependencies)
    }

    var body: some View {
        TabView {
            ScanView(viewModel: scanViewModel)
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }

            LogView(viewModel: logViewModel)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }

            SettingsView(viewModel: settingsViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView(dependencies: .makePreview())
}
