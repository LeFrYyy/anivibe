import SwiftUI

enum AppTab: Hashable { case home, catalog, library, profile }

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: (session.user?.id ?? "guest") + String(scenePhase == .active)) {
            let user = session.user?.id
            env.community.clear(for: user)
            guard scenePhase == .active, let user, let service = env.communityService else { return }
            await env.community.refresh(service: service, userId: user)
            let polling = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
                    guard session.user?.id == user else { break }
                    await env.community.refresh(service: service, userId: user)
                }
            }
            defer { polling.cancel() }
            let stream = await service.invalidations(userId: user)
            for await _ in stream {
                guard !Task.isCancelled, session.user?.id == user else { break }
                await env.community.refresh(service: service, userId: user)
            }
        }
        .overlay(alignment: .top) {
            if let toast = env.community.levelToast {
                Label(toast, systemImage: "sparkles").font(.headline).padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20)).padding(16)
                    .transition(AppMotion.panelTransition(reduceMotion: reduceMotion)).allowsHitTesting(false)
            }
        }
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: env.community.levelToast)
        .task(id: env.community.levelToast) {
            guard env.community.levelToast != nil else { return }
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            env.community.levelToast = nil
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
