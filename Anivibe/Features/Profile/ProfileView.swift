import SwiftUI
import AnivibeCore

struct ProfileView: View {
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
            LabeledContent("Email", value: user.email ?? "—")
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Режим", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
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
            .buttonStyle(.borderedProminent)
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
