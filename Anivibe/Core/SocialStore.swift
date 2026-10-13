import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class SocialStore {
    private(set) var profile: UserProfile?
    private(set) var friendships: [Friendship] = []
    private(set) var peers: [String: UserProfile] = [:]
    private(set) var searchResults: [UserProfile] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isSearching = false
    var errorMessage: String?
    var searchError: String?
    @ObservationIgnored private var service: SupabaseSocialService?
    @ObservationIgnored private var currentUserID: String?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var searchID = UUID()

    func load(service: SupabaseSocialService?, userID: String?) async {
        self.service = service
        if currentUserID != userID {
            profile = nil; friendships = []; peers = [:]; searchResults = []
            errorMessage = nil; searchError = nil; searchID = UUID(); isSearching = false
        }
        currentUserID = userID
        let operation = UUID(); loadID = operation
        guard let service, let userID else { isLoading = false; return }
        isLoading = true; errorMessage = nil
        defer { if loadID == operation { isLoading = false } }
        do {
            let own = try await service.ownProfile()
            guard loadID == operation, currentUserID == userID, own.userID == userID, !Task.isCancelled else { return }
            profile = own
            if own.avatarPath != nil {
                Task { _ = try? await AvatarImageLoader.shared.image(service: service, viewer: userID, target: own.userID, revision: own.avatarPath ?? own.updatedAt) }
            }
            let edges = try await service.friendships()
            let ids = Array(Set(edges.map { $0.peerID(for: userID) }))
            var profiles: [UserProfile] = []
            for offset in stride(from: 0, to: ids.count, by: 100) {
                profiles += try await service.profiles(ids: Array(ids[offset..<min(offset + 100, ids.count)]))
                guard loadID == operation, currentUserID == userID, !Task.isCancelled else { return }
            }
            guard loadID == operation, currentUserID == userID, !Task.isCancelled else { return }
            friendships = edges
            peers = Dictionary(uniqueKeysWithValues: profiles.map { ($0.userID, $0) })
            for peer in profiles.prefix(10) where peer.avatarPath != nil {
                Task { _ = try? await AvatarImageLoader.shared.image(service: service, viewer: userID, target: peer.userID, revision: peer.avatarPath ?? peer.updatedAt) }
            }
        } catch {
            if loadID == operation, !Task.isCancelled { errorMessage = message(error) }
        }
    }
    func save(_ draft: ProfileDraft) async -> Bool {
        guard !isSaving, let service, let account = currentUserID else { return false }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await service.updateProfile(draft, expectedUserID: account)
            guard currentUserID == account, updated.userID == account else { return false }
            profile = updated; return true
        } catch {
            if currentUserID == account { errorMessage = message(error) }; return false
        }
    }
    func setAvatar(_ jpeg: Data?) async {
        guard !isSaving, let service, let account = currentUserID else { return }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.setAvatar(jpeg: jpeg, expectedUserID: account)
            AvatarImageLoader.shared.reset()
            if currentUserID == account { await load(service: service, userID: account) }
        } catch { if currentUserID == account { errorMessage = message(error) } }
    }
    func clearSearch() {
        searchID = UUID(); searchResults = []; searchError = nil; isSearching = false
    }
    func search(_ username: String) async {
        guard let service, let account = currentUserID else { return }
        let operation = UUID(); searchID = operation
        isSearching = true; searchError = nil; searchResults = []
        defer { if searchID == operation { isSearching = false } }
        do {
            let results = try await service.searchProfiles(username: username)
            guard searchID == operation, currentUserID == account, !Task.isCancelled else { return }
            searchResults = results
        } catch { if searchID == operation, currentUserID == account { searchError = message(error) } }
    }
    func act(targetID: String, action: FriendAction) async {
        guard !isSaving, let service, let account = currentUserID else { return }
        isSaving = true; errorMessage = nil
        do {
            try await service.friendAction(targetID: targetID, action: action, expectedUserID: account)
            AvatarImageLoader.shared.reset()
            if currentUserID == account { await load(service: service, userID: account) }
        } catch { if currentUserID == account { errorMessage = message(error) } }
        isSaving = false
    }
    func edge(with peerID: String) -> Friendship? {
        guard let currentUserID else { return nil }
        return friendships.first { $0.peerID(for: currentUserID) == peerID }
    }
    private func message(_ error: Error) -> String {
        if let error = error as? SocialError { return error.userMessage }
        if let error = error as? AuthError { return error.userMessage }
        if let error = error as? APIError { return error.userMessage }
        return "Не удалось загрузить данные. Проверьте подключение и повторите попытку."
    }
}

/// Friend-profile pages remain scoped to both the target and viewing account.
@Observable
@MainActor
final class SocialProfileStore {
    let targetID: String
    private(set) var details: SocialProfileDetails?
    private(set) var history: [HistoryItem] = []
    private(set) var entries: [LibraryEntry] = []
    private(set) var isLoading = false
    private(set) var isPaging = false
    private(set) var historyHasMore = false
    private(set) var libraryHasMore = false
    var errorMessage: String?
    @ObservationIgnored private var operation = UUID()
    @ObservationIgnored private var viewer: String?
    @ObservationIgnored private var historyOffset = 0
    @ObservationIgnored private var libraryOffset = 0
    init(targetID: String) { self.targetID = targetID }
    func clear() {
        operation = UUID(); details = nil; history = []; entries = []; historyOffset = 0; libraryOffset = 0
        historyHasMore = false; libraryHasMore = false; isLoading = false; isPaging = false; errorMessage = nil
    }
    func load(service: SupabaseSocialService?, viewerID: String?) async {
        clear(); viewer = viewerID
        guard let service, let viewerID else { errorMessage = "Войдите в аккаунт, чтобы открыть профиль."; return }
        let request = operation; isLoading = true
        defer { if operation == request { isLoading = false } }
        do {
            let response = try await service.socialProfile(targetID: targetID, expectedUserID: viewerID)
            guard request == operation, viewer == viewerID, !Task.isCancelled else { return }
            applyMetadata(response)
            history = response.history; entries = response.library
            historyOffset = response.history.count; libraryOffset = response.library.count
        } catch { if request == operation, !Task.isCancelled { errorMessage = message(error) } }
    }
    func moreHistory(service: SupabaseSocialService?) async { await page(service: service, historyPage: true) }
    func moreLibrary(service: SupabaseSocialService?) async { await page(service: service, historyPage: false) }
    private func page(service: SupabaseSocialService?, historyPage: Bool) async {
        guard let service, let viewer, !isLoading, !isPaging,
              (historyPage ? historyHasMore : libraryHasMore) else { return }
        let request = operation; isPaging = true; errorMessage = nil
        defer { if operation == request { isPaging = false } }
        do {
            let response = try await service.socialProfile(targetID: targetID,
                historyOffset: historyPage ? historyOffset : 0, libraryOffset: historyPage ? 0 : libraryOffset, expectedUserID: viewer)
            guard request == operation, !Task.isCancelled else { return }
            // Permission changes wipe formerly visible data; no stale private rows.
            applyMetadata(response, updateHistory: historyPage, updateLibrary: !historyPage)
            if historyPage, response.historyAllowed {
                historyOffset += response.history.count
                let ids = Set(history.map(\.id)); history += response.history.filter { !ids.contains($0.id) }
            }
            if !historyPage, response.libraryAllowed {
                libraryOffset += response.library.count
                let ids = Set(entries.map(\.id)); entries += response.library.filter { !ids.contains($0.id) }
            }
        } catch {
            if request == operation, !Task.isCancelled {
                if error as? SocialError == .denied { clear() }
                errorMessage = message(error)
            }
        }
    }
    private func applyMetadata(_ response: SocialProfileDetails, updateHistory: Bool = true, updateLibrary: Bool = true) {
        details = response
        if !response.historyAllowed { history = [] }
        if !response.libraryAllowed { entries = [] }
        if updateHistory || !response.historyAllowed { historyHasMore = response.historyHasMore }
        if updateLibrary || !response.libraryAllowed { libraryHasMore = response.libraryHasMore }
    }
    private func message(_ error: Error) -> String {
        if let error = error as? SocialError { return error.userMessage }
        if let error = error as? AuthError { return error.userMessage }
        return "Не удалось загрузить профиль. Проверьте подключение и обновите экран."
    }
}
