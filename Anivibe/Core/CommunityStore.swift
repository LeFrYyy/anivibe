import SwiftUI
import AnivibeCore

@Observable @MainActor
final class CommunityStore {
    private(set) var hub: CommunityHub?
    private(set) var isLoading = false
    private(set) var isMutating = false
    var error: String?
    var confirmation: String?
    var levelToast: String?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadRequest = UUID()
    @ObservationIgnored private var pendingPurchases: [String: UUID] = [:]

    func clear(for userId: String?) {
        guard account != userId else { return }
        account = userId; generation = UUID(); loadRequest = UUID(); hub = nil; error = nil; confirmation = nil; levelToast = nil
        pendingPurchases = [:]; isLoading = false; isMutating = false
    }
    func refresh(service: SupabaseCommunityService?, userId: String?, force: Bool = false) async {
        clear(for: userId)
        guard let service, let userId, !isLoading || force else { return }
        let request = generation; let load = UUID(); loadRequest = load; isLoading = true
        defer { if generation == request, loadRequest == load { isLoading = false } }
        do {
            let result = try await service.hub(userId: userId)
            guard generation == request, loadRequest == load, account == userId, result.userId.lowercased() == userId.lowercased(), !Task.isCancelled else { return }
            hub = result; error = nil
            for item in result.items where item.owned { pendingPurchases[item.id] = nil }
            if let level = result.notifications.first(where: { $0.kind == "level_up" && !$0.read }) {
                let claimed = try await service.readNotification(level.id, userId: userId)
                if claimed, generation == request, account == userId, !Task.isCancelled { levelToast = level.title }
            }
        } catch { if generation == request, loadRequest == load, !Task.isCancelled { self.error = Self.message(error) } }
    }
    func purchase(_ item: CommunityItem, service: SupabaseCommunityService?, userId: String?) async {
        guard let service, let userId, account == userId, !isMutating else { return }
        let request = generation; isMutating = true; confirmation = nil; error = nil
        let nonce = pendingPurchases[item.id] ?? UUID(); pendingPurchases[item.id] = nonce
        defer { if generation == request { isMutating = false } }
        do {
            let receipt = try await service.purchase(itemId: item.id, requestId: nonce, userId: userId)
            guard generation == request, account == userId, !Task.isCancelled else { return }
            confirmation = receipt.charged == 0 ? "Предмет уже в инвентаре. Монеты не списаны." : "Покупка подтверждена сервером."
            await refresh(service: service, userId: userId, force: true)
        } catch { if generation == request { self.error = Self.message(error) + " Обновите баланс перед повтором." } }
    }
    func equip(_ item: CommunityItem, service: SupabaseCommunityService?, userId: String?) async {
        guard let slot = item.slot, let service, let userId else { return }
        await mutate(service: service, userId: userId) {
            try await service.equip(slot: slot, itemId: item.equipped ? nil : item.id, userId: userId)
        }
    }
    func preferences(invites: String, hide: Bool, service: SupabaseCommunityService?, userId: String?) async {
        guard let service, let userId else { return }
        await mutate(service: service, userId: userId) {
            try await service.preferences(invites: invites, hideWatching: hide, userId: userId)
        }
    }
    func read(_ notice: CommunityNotice, service: SupabaseCommunityService?, userId: String?) async {
        guard !notice.read, let service, let userId else { return }
        await mutate(service: service, userId: userId) { _ = try await service.readNotification(notice.id, userId: userId) }
    }
    private func mutate(service: SupabaseCommunityService, userId: String, action: () async throws -> Void) async {
        guard account == userId, !isMutating else { return }
        let request = generation; isMutating = true; error = nil; confirmation = nil
        defer { if generation == request { isMutating = false } }
        do { try await action(); guard generation == request, !Task.isCancelled else { return }; await refresh(service: service, userId: userId, force: true) }
        catch { if generation == request { self.error = Self.message(error) } }
    }
    static func message(_ error: Error) -> String {
        if let error = error as? CommunityError { return error.userMessage }
        if let error = error as? AuthError { return error.userMessage }
        if let error = error as? APIError { return error.userMessage }
        return "Нет связи с сервером. Данные и награды ожидают подтверждения; проверьте подключение."
    }
}
