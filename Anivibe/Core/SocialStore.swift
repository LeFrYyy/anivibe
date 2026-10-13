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
            let edges = try await service.friendships()
            let ids = Array(Set(edges.map { $0.peerID(for: userID) }))
            let profiles = try await service.profiles(ids: ids)
            guard loadID == operation, currentUserID == userID, !Task.isCancelled else { return }
            friendships = edges
            peers = Dictionary(uniqueKeysWithValues: profiles.map { ($0.userID, $0) })
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
            if currentUserID == account { await load(service: service, userID: account) }
        } catch { if currentUserID == account { errorMessage = message(error) } }
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
