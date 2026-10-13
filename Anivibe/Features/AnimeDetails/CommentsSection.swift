import SwiftUI
import AnivibeCore

struct CommentsSection: View {
    let animeID: Int
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var rows: [TitleComment] = []
    @State private var text = ""
    @State private var popular = false
    @State private var busy = false
    @State private var loading = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var notice: String?
    @State private var reporting: TitleComment?
    @State private var deleting: TitleComment?
    @State private var generation = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Комментарии").font(.title3.bold())
            if session.user == nil {
                Text("Войдите в профиль, чтобы читать и писать комментарии.").foregroundStyle(.secondary)
            } else {
                Picker("Порядок", selection: $popular) {
                    Text("Новые").tag(false); Text("Популярные").tag(true)
                }.pickerStyle(.segmented).disabled(busy || loading)
                TextField("Ваш комментарий", text: $text, axis: .vertical).lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                Text("\(text.unicodeScalars.count)/2000 · Имя автора видно согласно приватности профиля").font(.caption).foregroundStyle(.secondary)
                Button("Отправить") { Task { await action("create", content: text) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 2000)
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                Button("Обновить") { Task { await load(reset: true) } }.disabled(loading || busy)
                if rows.isEmpty && !loading && error == nil { Text("Пока нет комментариев.").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProfileAvatarView(userID: row.authorID)
                            VStack(alignment: .leading) {
                                Text(verbatim: row.authorName).font(.subheadline.bold())
                                Text(String(row.createdAt.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                if row.authorID == session.user?.id { Button("Удалить", role: .destructive) { deleting = row } }
                                else { Button("Пожаловаться") { reporting = row } }
                            } label: { Image(systemName: "ellipsis") }
                        }
                        Text(verbatim: row.body).textSelection(.enabled)
                        HStack {
                            Button { Task { await action("react", row: row, value: row.myReaction == 1 ? 0 : 1) } } label: {
                                Label("\(row.likes)", systemImage: row.myReaction == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                            }
                            Button { Task { await action("react", row: row, value: row.myReaction == -1 ? 0 : -1) } } label: {
                                Label("\(row.dislikes)", systemImage: row.myReaction == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            }
                        }.buttonStyle(.bordered).disabled(busy || loading)
                    }.padding(12).background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
                if loading || busy { ProgressView() }
                if hasMore { Button("Показать ещё") { Task { await load(reset: false) } }.disabled(loading || busy) }
            }
        }.padding(.horizontal, Theme.Spacing.l)
        .task(id: "\(animeID):\(session.user?.id ?? "guest"):\(popular)") {
            generation = UUID(); rows = []; text = ""; error = nil; notice = nil; hasMore = false; busy = false; loading = false
            await load(reset: true)
        }
        .confirmationDialog("Удалить ваш комментарий?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let row = deleting { Button("Удалить", role: .destructive) { Task { await action("delete", row: row) }; deleting = nil } }
        }
        .confirmationDialog("Причина жалобы", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
            if let row = reporting {
                ForEach(["Спам", "Оскорбления", "Неприемлемый контент", "Другое"], id: \.self) { reason in
                    Button(reason) { Task { await action("report", row: row, content: reason) }; reporting = nil }
                }
            }
        }
    }
    @MainActor private func load(reset: Bool) async {
        guard let service = env.socialService, let account = session.user?.id else { return }
        let token = generation
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let page = try await service.comments(animeID: animeID, offset: reset ? 0 : rows.count, popular: popular, expectedUserID: account)
            guard token == generation, session.user?.id == account, !Task.isCancelled else { return }
            if reset { rows = page } else {
                let ids = Set(rows.map(\.id)); rows += page.filter { !ids.contains($0.id) }
            }
            hasMore = page.count == 20
        } catch { if token == generation, !Task.isCancelled { self.error = message(error) } }
    }
    @MainActor private func action(_ kind: String, row: TitleComment? = nil, content: String = "", value: Int = 0) async {
        guard !busy, let service = env.socialService, let account = session.user?.id else { return }
        let token = generation
        busy = true; error = nil; notice = nil
        defer { if token == generation { busy = false } }
        do {
            try await service.commentAction(animeID: animeID, action: kind, commentID: row?.id, text: content, value: value, expectedUserID: account)
            guard token == generation, session.user?.id == account else { return }
            if kind == "create" { text = "" }
            if kind == "report" { notice = "Жалоба сохранена для проверки администратором." }
            else { await load(reset: true) }
        } catch { if token == generation { self.error = message(error) } }
    }
    private func message(_ error: Error) -> String {
        if let e = error as? SocialError {
            if e == .backendMissing { return "Комментарии не настроены. Примените миграцию avatars_comments." }
            return e.userMessage
        }
        if let e = error as? AuthError { return e.userMessage }
        return "Ошибка загрузки. Проверьте интернет и повторите запрос."
    }
}
