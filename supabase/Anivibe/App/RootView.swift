import SwiftUI

enum AppTab: Hashable { case home, catalog, library, profile }

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showSplash = true

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
                ProfileView()
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
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}
