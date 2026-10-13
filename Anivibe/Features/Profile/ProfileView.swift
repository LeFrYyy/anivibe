import SwiftUI
import AnivibeCore

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var social = SocialStore()
    @State private var editProfile = false
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library

    var body: some View {
        NavigationStack {
            List {
                if !session.isBackendConfigured {
                    localModeSection
                } else if let user = session.user {
                    accountSection(user)
                } else {
                    Section {
                        AuthFormView()
                    } header: {
                        Text("Аккаунт")
                    } footer: {
                        Text("Аккаунт нужен только для синхронизации списков, истории и прогресса между устройствами.")
                    }
                }
                statsSection
                Section {
                    NavigationLink { SettingsView() } label: { Label("Настройки", systemImage: "gearshape") }
                    NavigationLink { AboutView() } label: { Label("О приложении", systemImage: "info.circle") }
                }
            }
            .navigationTitle("Профиль")
            .task(id: session.user?.id) { await social.load(service: env.socialService, userID: session.user?.id) }
            .sheet(isPresented: $editProfile) {
                if let profile = social.profile { ProfileEditorView(store: social, profile: profile) }
            }
        }
    }

    private var localModeSection: some View {
        Section {
            Label("Локальный режим", systemImage: "iphone")
                .font(.headline)
            Text("Списки, история и прогресс сохраняются на этом устройстве. Чтобы включить вход и синхронизацию, настройте Supabase (см. README, раздел «Настройка backend»).")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func accountSection(_ user: AuthUser) -> some View {
        Section("Аккаунт") {
            if let profile = social.profile {
                HStack { ProfileAvatarView(userID: profile.userID, revision: profile.updatedAt, size: 64); Text(profile.displayName).font(.title3.bold()) }
                if let username = profile.username { Text("@" + username).foregroundStyle(Theme.textSecondary) }
                else { Text("Выберите username в настройках профиля").font(.footnote) }
                if !profile.bio.isEmpty { Text(verbatim: profile.bio) }
                LabeledContent("ID пользователя", value: profile.userID).textSelection(.enabled)
                LabeledContent("Дата регистрации", value: String(profile.createdAt.prefix(10)))
                LabeledContent("Видимость", value: profile.visibility.title)
                Button("Редактировать профиль") { editProfile = true }
                NavigationLink { FriendsView(store: social, userID: user.id) } label: { Label("Друзья", systemImage: "person.2") }
            }
            if social.isLoading { ProgressView("Загружаем профиль…") }
            if let error = social.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
                Button("Повторить загрузку профиля") { Task { await social.load(service: env.socialService, userID: user.id) } }
            }
            LabeledContent("Почта (только вам)", value: user.email ?? "—")
            HStack {
                Button {
                    Task { await session.syncIfNeeded(reason: .manual) }
                } label: {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(session.isSyncing)
                Spacer()
                if session.isSyncing { ProgressView() }
            }
            if let date = session.lastSync {
                LabeledContent("Последняя синхронизация", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let message = session.lastSyncMessage {
                Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Button("Выйти", role: .destructive) { Task { await session.signOut() } }
        }
    }

    private var statsSection: some View {
        Section("Статистика") {
            LabeledContent("Смотрю", value: "\(library.snapshot.entries(in: .watching).count)")
            LabeledContent("Просмотрено", value: "\(library.snapshot.entries(in: .completed).count)")
            LabeledContent("В избранном", value: "\(library.snapshot.favorites.count)")
            LabeledContent("Серий в истории", value: "\(library.snapshot.history.count)")
            if let error = library.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger).font(.footnote)
            }
        }
    }
}

struct AuthFormView: View {
    enum Mode: String, CaseIterable { case signIn = "Вход", signUp = "Регистрация", recover = "Восстановление" }

    @Environment(SessionStore.self) private var session
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var resendAfter = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Режим", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField("Электронная почта", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

            if mode != .recover {
                SecureField(mode == .signUp ? "Пароль (от 8 символов)" : "Пароль", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .padding(10)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            }

            if let pending = session.pendingConfirmationEmail {
                Text("Подтверждение: \(pending)").font(.footnote)
                TextField("Код из письма (6 цифр)", text: $confirmationCode)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                Button("Подтвердить код") { Task { await session.verifySignupCode(code: confirmationCode); confirmationCode = "" } }
                    .disabled(session.isBusy || confirmationCode.count != 6)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Button(context.date < resendAfter ? "Повторить через \(max(1, Int(resendAfter.timeIntervalSince(context.date)))) с" : "Отправить код повторно") {
                        resendAfter = Date().addingTimeInterval(60)
                        Task { await session.resendSignupCode() }
                    }.disabled(session.isBusy || context.date < resendAfter)
                }
            }
            Button("Войти через Google") { Task { await session.signInGoogle() } }.disabled(session.isBusy)

            if let error = session.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
            if let info = session.infoMessage {
                Text(info).font(.footnote).foregroundStyle(Theme.success)
            }

            Button {
                Task {
                    switch mode {
                    case .signIn: await session.signIn(email: email, password: password)
                    case .signUp: await session.signUp(email: email, password: password)
                    case .recover: await session.recover(email: email)
                    }
                    password = ""
                }
            } label: {
                HStack {
                    Spacer()
                    if session.isBusy { ProgressView() } else { Text(buttonTitle).fontWeight(.semibold) }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
            .disabled(session.isBusy || email.isEmpty || (mode != .recover && password.isEmpty))
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: return "Войти"
        case .signUp: return "Создать аккаунт"
        case .recover: return "Отправить письмо"
        }
    }
}
