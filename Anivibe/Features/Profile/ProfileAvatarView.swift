import SwiftUI

/// Short-lived signed links only; reset when account or profile revision changes.
struct ProfileAvatarView: View {
    let userID: String
    var revision: String = ""
    var size: CGFloat = 40
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: userID + revision + (session.user?.id ?? "guest")) {
            url = nil
            guard let account = session.user?.id else { return }
            let loaded = try? await env.socialService?.avatarURL(userID: userID, expectedUserID: account)
            guard !Task.isCancelled, session.user?.id == account else { return }
            url = loaded
        }
        .accessibilityLabel("Аватар")
    }
}
