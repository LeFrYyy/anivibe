import SwiftUI
import AnivibeCore

struct CommunityView: View {
    enum Section: String, CaseIterable { case friends = "Вместе", shop = "Магазин", inventory = "Моё", notices = "События" }
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var section: Section = .friends
    @State private var preferences = false
    @State private var pendingPurchase: CommunityItem?
    @State private var preview: CommunityItem?
    private var store: CommunityStore { env.community }
    private var visibleSections: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .friends: return AppFeatures.sharedWatchingEnabled
            case .shop, .inventory: return AppFeatures.friendshipShopEnabled
            case .notices: return AppFeatures.communityEnabled
            }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let hub = store.hub, hub.userId == session.user?.id {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Истории сближают").font(.title2.bold())
                            Text("Друзья \(hub.friends.count)/\(hub.friendCap) · \(hub.uniqueEpisodes) подтверждённых серий")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Label(hub.balance.formatted(), systemImage: "circle.circle.fill").font(.headline.monospacedDigit()).foregroundStyle(Theme.accent)
                            .accessibilityLabel("Баланс: \(hub.balance) монет")
                    }
                    Picker("Раздел", selection: $section) { ForEach(visibleSections, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    switch section {
                    case .friends: together(hub)
                    case .shop: items(hub.items.filter(\.available), inventory: false)
                    case .inventory: items(hub.items.filter(\.owned), inventory: true)
                    case .notices: notifications(hub)
                    }
                } else if session.user == nil {
                    ContentUnavailableView("Войдите в аккаунт", systemImage: "person.crop.circle", description: Text("Дружба, награды и покупки хранятся на сервере."))
                } else if store.isLoading {
                    ProgressView("Загружаем социальную систему…").frame(maxWidth: .infinity, minHeight: 180)
                }
                if store.isMutating { ProgressView("Ожидаем подтверждения сервера…") }
                if let confirmation = store.confirmation { Label(confirmation, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Theme.success) }
                if let error = store.error {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(Theme.danger)
                        Button("Обновить") { Task { await refresh() } }.buttonStyle(.bordered)
                    }.profilePanel()
                }
                Text("XP общий для пары, монеты — личные. Вознаграждение за одну каноническую серию выдаётся паре только один раз.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }.padding(16).padding(.bottom, 20)
        }.screenBackground().navigationTitle("Вместе в Anivibe").navigationBarTitleDisplayMode(.inline)
        .task(id: session.user?.id) {
            if let first = visibleSections.first { section = first }
            await refresh()
        }.refreshable { await refresh() }
        .toolbar { Button { preferences = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Приватность приглашений") }
        .sheet(isPresented: $preferences) { NavigationStack { CommunityPreferencesView() } }
        .sheet(item: $preview) { item in
            NavigationStack {
                VStack(spacing: 24) {
                    CosmeticMediaView(assetKey: item.assetKey, posterKey: item.posterKey, mime: item.mime, animate: true)
                        .frame(height: item.category == "avatar" ? 190 : 160).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(item.name).font(.title2.bold())
                    Text(item.owned ? "Уже в вашем инвентаре" : "\(item.price) монет").font(.headline)
                    if !item.owned {
                        Button("Купить") { preview = nil; pendingPurchase = item }.buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                    }
                    Text("Движение отключается при уменьшении движения и уходе приложения в фон.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }.padding(24).navigationTitle("Предпросмотр").toolbar { Button("Готово") { preview = nil } }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("Подтвердить покупку", isPresented: Binding(get: { pendingPurchase != nil }, set: { if !$0 { pendingPurchase = nil } }), titleVisibility: .visible) {
            if let item = pendingPurchase {
                Button("Купить за \(item.price) монет") { pendingPurchase = nil; Task { await store.purchase(item, service: env.communityService, userId: session.user?.id) } }
            }
            Button("Отмена", role: .cancel) { pendingPurchase = nil }
        } message: {
            if let item = pendingPurchase { Text("\(item.name). Точную цену, наличие и баланс проверит сервер. \(item.category == "friend_cap" ? "Улучшение постоянно; возврат не предусмотрен." : "Предмет сохранится в аккаунте.")") }
        }
        .onChange(of: session.user?.id) { _, _ in preview = nil; pendingPurchase = nil; preferences = false }
    }
    private func refresh() async {
        guard AppFeatures.communityEnabled else { return }
        await store.refresh(service: env.communityService, userId: session.user?.id)
    }
    @ViewBuilder private func together(_ hub: CommunityHub) -> some View {
        if AppFeatures.sharedWatchingEnabled, !hub.sessions.isEmpty {
            Text("Комнаты").font(.headline)
            ForEach(hub.sessions) { room in
                NavigationLink { WatchRoomView(roomId: room.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: room.status == "invited" ? "envelope.badge" : "play.rectangle.on.rectangle").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.animeTitle).font(.headline).lineLimit(2)
                            Text(room.episodeLabel + (room.status == "invited" ? " · приглашение" : " · в комнате")).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.profilePanel()
                }.buttonStyle(.plain)
            }
        }
        HStack { Text("Дружба и задания").font(.headline); Spacer(); Text(hub.day + " · сервер").font(.caption).foregroundStyle(Theme.textSecondary) }
        if hub.friends.isEmpty {
            ContentUnavailableView("Позовите своих", systemImage: "person.2", description: Text("Добавьте друга в разделе профиля. После принятия заявки здесь появится ваше общее развитие."))
        }
        ForEach(hub.friends) { friend in
            NavigationLink { FriendshipProgressView(peerId: friend.peerId) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ProfileAvatarView(userID: friend.peerId, revision: friend.avatarPath ?? "", size: 44, avatarAvailable: friend.avatarPath != nil)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(friend.name).font(.headline)
                            Text(friend.watching == true ? "Смотрит аниме" : "Уровень \(friend.level.level) · \(friend.episodes) серий вместе").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }
                    ProgressView(value: friend.level.progress).tint(Theme.accent)
                    HStack { Text("Сегодня: \(min(friend.dailyCompleted, hub.dailyGoal))/\(hub.dailyGoal)"); Spacer(); Text(friend.dailyRewarded ? "Бонус получен" : "+\(hub.dailyXp) XP · +\(hub.dailyCoins) монет") }
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }.profilePanel()
            }.buttonStyle(.plain)
        }
    }
    @ViewBuilder private func items(_ catalog: [CommunityItem], inventory: Bool) -> some View {
        if catalog.isEmpty { ContentUnavailableView(inventory ? "Здесь будут ваши предметы" : "Магазин пока пуст", systemImage: "bag", description: Text("Монеты за совместный просмотр можно обменять на оформление и дополнительные места для друзей.")) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 14) {
            ForEach(catalog) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Button { preview = item } label: {
                        if item.category == "friend_cap" {
                            Image(systemName: "person.3.sequence.fill").font(.largeTitle).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, minHeight: 110)
                        } else {
                            CosmeticMediaView(assetKey: item.assetKey, posterKey: item.posterKey, mime: item.mime, animate: false)
                                .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Предпросмотр: " + item.name)
                    Text(item.name).font(.headline).lineLimit(2).frame(minHeight: 42, alignment: .topLeading)
                    Text(categoryLabel(item.category)).font(.caption).foregroundStyle(Theme.textSecondary)
                    if item.owned {
                        if item.slot != nil {
                            Button(item.equipped ? "Снять" : "Надеть") { Task { await store.equip(item, service: env.communityService, userId: session.user?.id) } }
                                .buttonStyle(.bordered).disabled(store.isMutating)
                        } else { Label("Активно", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.success) }
                    } else {
                        Button { pendingPurchase = item } label: { Label("\(item.price)", systemImage: "circle.circle.fill").frame(maxWidth: .infinity, minHeight: 32) }
                            .buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent).disabled(store.isMutating)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
    @ViewBuilder private func notifications(_ hub: CommunityHub) -> some View {
        if hub.notifications.isEmpty { ContentUnavailableView("Пока тихо", systemImage: "bell", description: Text("Приглашения, награды и новые уровни появятся здесь.")) }
        ForEach(hub.notifications) { notice in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: notice.kind == "level_up" ? "sparkles" : "bell").foregroundStyle(Theme.accent)
                    Text(notice.title).font(.subheadline.weight(notice.read ? .regular : .semibold)); Spacer()
                    if !notice.read { Circle().fill(Theme.accent).frame(width: 7, height: 7).accessibilityLabel("Не прочитано") }
                }
                if let reason = notice.payload.reason { Text(reason).font(.caption).foregroundStyle(Theme.textSecondary) }
                if AppFeatures.sharedWatchingEnabled, let id = notice.payload.sessionId { NavigationLink("Открыть комнату") { WatchRoomView(roomId: id) } }
                if !notice.read { Button("Прочитано") { Task { await store.read(notice, service: env.communityService, userId: session.user?.id) } }.font(.caption).disabled(store.isMutating) }
            }.profilePanel()
        }
    }
    private func categoryLabel(_ key: String) -> String {
        switch key { case "avatar": return "Анимированный аватар"; case "banner": return "Баннер"; case "animated_banner": return "Живой баннер"; default: return "Лимит друзей" }
    }
}

struct FriendshipProgressView: View {
    let peerId: String
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    var body: some View {
        ScrollView {
            if let hub = env.community.hub, let friend = hub.friends.first(where: { $0.peerId == peerId }) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        ProfileAvatarView(userID: peerId, revision: friend.avatarPath ?? "", size: 76, avatarAvailable: friend.avatarPath != nil)
                        VStack(alignment: .leading, spacing: 6) { Text(friend.name).font(.title2.bold()); Text(friend.username.map { "@" + $0 } ?? "Ваш друг").foregroundStyle(Theme.textSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Уровень \(friend.level.level)", systemImage: "sparkles").font(.title.bold()).foregroundStyle(Theme.accent)
                        ProgressView(value: friend.level.progress).tint(Theme.accent)
                        Text("\(friend.level.inLevel)/\(friend.level.needed) XP до следующего уровня").font(.subheadline)
                        Text("Всего \(friend.level.xp) XP · \(friend.episodes) серий вместе").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text("Друзья с " + readableDate(friend.startedAt)).font(.caption).foregroundStyle(Theme.textSecondary)
                        if let last = friend.lastWatchAt { Text("Последний совместный просмотр: " + readableDate(last)).font(.caption).foregroundStyle(Theme.textSecondary) }
                    }.profilePanel()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Сегодня — \(hub.dailyGoal) серий вместе").font(.headline)
                        ProgressView(value: Double(min(friend.dailyCompleted, hub.dailyGoal)), total: Double(hub.dailyGoal))
                        Text("\(friend.dailyCompleted)/\(hub.dailyGoal) · \(friend.dailyRewarded ? "бонус получен" : "+\(hub.dailyXp) XP и +\(hub.dailyCoins) монет каждому")").font(.subheadline)
                        Text("Серверный день: \(hub.day). Повторные серии не продвигают задание.").font(.caption).foregroundStyle(Theme.textSecondary)
                    }.profilePanel()
                    if AppFeatures.sharedWatchingEnabled {
                        NavigationLink { WatchInviteView(peerId: peerId) } label: { Label("Смотреть вместе", systemImage: "play.rectangle.on.rectangle").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                    }
                    Text("По умолчанию: каждому нужно подтвердить минимум 90% серии, из них 80% — одновременно. Перемотка и ожидание не засчитываются; точные пороги задаёт сервер.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }.padding(20)
            } else { ContentUnavailableView("Дружба недоступна", systemImage: "person.2", description: Text("Обновите список или проверьте, что заявка принята.")) }
        }.screenBackground().navigationTitle("Ваше развитие").navigationBarTitleDisplayMode(.inline)
        .task(id: session.user?.id) {
            if AppFeatures.sharedWatchingEnabled {
                await env.community.refresh(service: env.communityService, userId: session.user?.id)
            }
        }
    }
    private func readableDate(_ raw: String) -> String { String(raw.prefix(10)) }
}

private struct CommunityPreferencesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if let hub = env.community.hub {
                Section("Приватность") {
                    Toggle("Приглашения от друзей", isOn: Binding(get: { hub.invitePolicy == "friends" }, set: { enabled in
                        Task { await env.community.preferences(invites: enabled ? "friends" : "none", hide: hub.hideWatching, service: env.communityService, userId: session.user?.id) }
                    }))
                    Toggle("Скрыть статус просмотра", isOn: Binding(get: { hub.hideWatching }, set: { enabled in
                        Task { await env.community.preferences(invites: hub.invitePolicy, hide: enabled, service: env.communityService, userId: session.user?.id) }
                    }))
                }.disabled(env.community.isMutating)
                Section { Text("Скрытие статуса не скрывает состояние текущей комнаты от её участника. Настройки применяются после подтверждения сервера.") }
                if let error = env.community.error { Text(error).foregroundStyle(Theme.danger) }
            }
        }.navigationTitle("Приглашения и статус").toolbar { Button("Готово") { dismiss() } }
    }
}
