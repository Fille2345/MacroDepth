// App/MacroDepthApp.swift

import SwiftUI

@main
struct MacroDepthApp: App {
    @State private var dependencies = AppDependencies.makeForCurrentProcess()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .task { await dependencies.health.observeChanges() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                dependencies.startPhotoCleanup()
                // Weight may have been logged in Health while the app was away.
                dependencies.health.requestSync()
            }
        }
    }
}
