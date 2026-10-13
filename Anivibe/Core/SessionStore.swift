import SwiftUI
import AnivibeCore

/// Состояние авторизации и синхронизации. Без настроенного Supabase — локальный режим.
@Observable
@MainActor
final class SessionStore {
    enum SyncReason { case manual, launch, foreground, background, localChange }

    private(set) var user: AuthUser?
    private(set) var isBusy = false
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastSyncMessage: String?
    var errorMessage: String?
    var infoMessage: String?
    private(set) var pendingConfirmationEmail: String?
    @ObservationIgnored private var oauth: GoogleOAuthCoordinator?

    private let auth: SupabaseAuthClient?
    private let sync: SupabaseSyncService?
    private let library: LibraryStore
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    var isBackendConfigured: Bool { auth != nil }
    var isSignedIn: Bool { user != nil }

    init(auth: SupabaseAuthClient?, sync: SupabaseSyncService?, library: LibraryStore) {
        self.auth = auth
        self.sync = sync
        self.library = library
        library.onLocalChange = { [weak self] in self?.scheduleSync() }
    }

    func restore() async {
        guard let auth else { return }
        user = await auth.currentSession?.user
        do { try await library.repository.switchAccount(userID: user?.id); await library.refresh() }
        catch { errorMessage = "Не удалось открыть библиотеку аккаунта. Исходный файл сохранён."; user = nil; return }
        lastSync = library.snapshot.lastSyncAt
        await syncIfNeeded(reason: .launch)
    }

    func signIn(email: String, password: String) async {
        await perform {
            let session = try await self.auth!.signIn(email: email, password: password)
            try await self.library.repository.switchAccount(userID: session.user.id)
            await self.library.refresh()
            self.user = session.user
            await self.syncIfNeeded(reason: .manual)
        }
    }

    func signUp(email: String, password: String) async {
        await perform {
            do {
                let session = try await self.auth!.signUp(email: email, password: password)
                try await self.library.repository.switchAccount(userID: session.user.id)
                await self.library.refresh()
                self.user = session.user
                await self.syncIfNeeded(reason: .manual)
            } catch AuthError.confirmationRequired {
                self.pendingConfirmationEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                self.infoMessage = "Проверьте почту и введите код подтверждения. Повторная отправка ограничена сервером."
            }
        }
    }

    func verifySignupCode(code: String) async {
        guard let email = pendingConfirmationEmail else { return }
        await perform {
            let session = try await self.auth!.verifySignupCode(email: email, code: code)
            try await self.library.repository.switchAccount(userID: session.user.id)
            await self.library.refresh()
            self.user = session.user; self.pendingConfirmationEmail = nil
            await self.syncIfNeeded(reason: .manual)
        }
    }
    func resendSignupCode() async {
        guard let email = pendingConfirmationEmail else { return }
        await perform { try await self.auth!.resendSignupCode(email: email); self.infoMessage = "Если отправка разрешена, новый код придёт на почту." }
    }
    func signInGoogle() async {
        await perform {
            let coordinator = GoogleOAuthCoordinator(); self.oauth = coordinator
            defer { self.oauth = nil }
            let result = try await coordinator.authorize { redirect, challenge in
                await self.auth!.googleAuthorizationURL(redirectURL: redirect, challenge: challenge)
            }
            let session = try await self.auth!.exchangeOAuthCode(result.code, verifier: result.verifier)
            try await self.library.repository.switchAccount(userID: session.user.id)
            await self.library.refresh()
            self.user = session.user
            await self.syncIfNeeded(reason: .manual)
        }
    }

    func recover(email: String) async {
        await perform {
            try await self.auth!.recoverPassword(email: email)
            self.infoMessage = "Если аккаунт существует, на \(email) отправлено письмо для восстановления."
        }
    }

    func signOut() async {
        guard let auth else { return }
        debounceTask?.cancel()
        await auth.signOut()
        user = nil
        do { try await library.repository.switchAccount(userID: nil); await library.refresh() }
        catch { errorMessage = "Не удалось восстановить локальную библиотеку. Файл не изменён." }
        lastSync = nil
        lastSyncMessage = nil
    }

    func syncIfNeeded(reason: SyncReason) async {
        guard let sync, user != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await sync.sync()
            lastSync = report.finishedAt
            lastSyncMessage = "Отправлено: \(report.pushed), получено: \(report.pulled)"
            await library.refresh()
        } catch let e as AuthError {
            if e == .sessionExpired || e == .notSignedIn { user = nil }
            lastSyncMessage = e.userMessage
        } catch let e as APIError {
            lastSyncMessage = "Синхронизация не удалась: \(e.userMessage)"
        } catch {
            lastSyncMessage = "Синхронизация не удалась."
        }
    }

    /// Изменения библиотеки отправляются пачкой через 8 секунд тишины.
    private func scheduleSync() {
        guard sync != nil, user != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.syncIfNeeded(reason: .localChange)
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        guard auth != nil else { errorMessage = "Backend не настроен."; return }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do { try await work() } catch let e as AuthError {
            if e == .confirmationRequired { infoMessage = e.userMessage } else { errorMessage = e.userMessage }
        } catch let e as APIError {
            errorMessage = e.userMessage
        } catch {
            errorMessage = "Не удалось выполнить действие."
        }
    }
}
