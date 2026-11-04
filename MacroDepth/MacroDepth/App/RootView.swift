// App/RootView.swift

import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case dashboard
        case scan
        case recipes
        case log
        case settings
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = Tab.dashboard
    @State private var dashboardViewModel: DashboardViewModel
    @State private var progressViewModel: ProgressTrackerViewModel
    @State private var scanViewModel: ScanViewModel
    @State private var recipesViewModel: RecipesViewModel
    @State private var logViewModel: LogViewModel
    @State private var onboardingViewModel: OnboardingViewModel
    private let settingsViewModel: SettingsViewModel
    private let isPreview: Bool

    init(dependencies: AppDependencies) {
        _dashboardViewModel = State(initialValue: DashboardViewModel(persistence: dependencies.persistence))
        _progressViewModel = State(initialValue: ProgressTrackerViewModel(persistence: dependencies.persistence))
        _scanViewModel = State(initialValue: ScanViewModel(dependencies: dependencies))
        _recipesViewModel = State(initialValue: RecipesViewModel(persistence: dependencies.persistence))
        _logViewModel = State(initialValue: LogViewModel(persistence: dependencies.persistence))
        _onboardingViewModel = State(initialValue: OnboardingViewModel(persistence: dependencies.persistence))
        settingsViewModel = SettingsViewModel(dependencies: dependencies)
        isPreview = dependencies.mode == .preview
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                viewModel: dashboardViewModel,
                progressViewModel: progressViewModel,
                onQuickLog: { selectedTab = .scan }
            )
                .tabItem { Label("Dashboard", systemImage: "chart.pie") }
                .tag(Tab.dashboard)

            ScanView(viewModel: scanViewModel)
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
                .tag(Tab.scan)

            RecipesView(viewModel: recipesViewModel, onUseInScan: { recipe in
                scanViewModel.prefillNotes(recipe.scanNotes)
                selectedTab = .scan
            })
            .tabItem { Label("Recipes", systemImage: "fork.knife") }
            .tag(Tab.recipes)

            LogView(viewModel: logViewModel)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(Tab.log)

            SettingsView(viewModel: settingsViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .sheet(isPresented: isShowingOnboarding) {
            OnboardingView(viewModel: onboardingViewModel, onFinished: { hasCompletedOnboarding = true })
        }
    }

    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding && !isPreview },
            set: { _ in }   // Only finishing the flow dismisses it.
        )
    }
}

#Preview {
    RootView(dependencies: .makePreview())
}
