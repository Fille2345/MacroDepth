// App/MacroDepthApp.swift

import SwiftUI

@main
struct MacroDepthApp: App {
    @State private var dependencies = AppDependencies.makeForCurrentProcess()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
