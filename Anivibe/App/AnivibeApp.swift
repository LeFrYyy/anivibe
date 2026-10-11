import SwiftUI

@main
struct AnivibeApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.library)
                .environment(environment.session)
                .environment(environment.settings)
                .preferredColorScheme(environment.settings.appearance.colorScheme)
                .tint(Theme.accent)
                .task { await environment.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            environment.handleScenePhase(phase)
        }
    }
}
