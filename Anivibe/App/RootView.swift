import SwiftUI

enum AppTab: Hashable { case home, catalog, library, profile }

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                HomeView(openCatalog: { tab = .catalog })
                    .tabItem { Label("Главная", systemImage: "house") }
                    .tag(AppTab.home)
                CatalogView()
                    .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
                    .tag(AppTab.catalog)
                LibraryView()
                    .tabItem { Label("Библиотека", systemImage: "books.vertical") }
                    .tag(AppTab.library)
                ProfileView(openCollections: { tab = .home })
                    .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            do { try await Task.sleep(nanoseconds: 450_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.fade(reduceMotion: reduceMotion)) { showSplash = false }
        }
    }
}
