import SwiftUI
import AVFoundation
import AnivibeCore
import ImageIO

/// Lists use a static poster. A selected preview/profile animates only while visible and active.
struct CosmeticMediaView: View {
    let assetKey: String?
    var posterKey: String? = nil
    let mime: String?
    var animate = false
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var animator: CosmeticLoop?
    @State private var poster: UIImage?
    @State private var loadedKey = ""
    @State private var powerSaving = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var canAnimate: Bool { animate && !reduceMotion && scenePhase == .active && !powerSaving && mime == "video/mp4" }
    private var posterIdentity: String { posterKey ?? assetKey ?? "" }
    private var playbackIdentity: String { (assetKey ?? "") + String(canAnimate) }
    var body: some View {
        ZStack {
            Theme.surfaceElevated
            if let url = resource(posterIdentity, ext: "png"), url.scheme == "https" {
                PosterImage(url: url, cornerRadius: 0)
            } else if let poster, loadedKey == posterIdentity {
                Image(uiImage: poster).resizable().scaledToFill()
            } else { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.accent) }
            if canAnimate, let animator { CosmeticVideoSurface(player: animator.player) }
        }.clipped()
        .task(id: posterIdentity) {
            let key = posterIdentity; poster = nil; loadedKey = key
            guard let url = resource(key, ext: "png"), url.isFileURL else { return }
            let image = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 768, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            guard !Task.isCancelled, key == posterIdentity else { return }; poster = image
        }
        .task(id: playbackIdentity) {
            animator?.stop(); animator = nil
            guard canAnimate, let key = assetKey, let url = resource(key, ext: "mp4") else { return }
            animator = CosmeticLoop(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in powerSaving = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in powerSaving = true; animator?.stop(); animator = nil }
        .onDisappear { animator?.stop(); animator = nil }
        .accessibilityHidden(true)
    }
    private func resource(_ key: String, ext: String) -> URL? {
        if key.hasPrefix("storage:"), let supabase = env.configuration.supabase {
            let leaf = String(key.dropFirst(8))
            guard leaf.hasSuffix("." + ext), leaf.range(of: "^[0-9a-f]{64}\\.(png|mp4)$", options: .regularExpression) != nil else { return nil }
            return supabase.url.appendingPathComponent("storage/v1/object/public/community-media").appendingPathComponent(leaf)
        }
        guard key.range(of: "^[a-z0-9_-]{1,60}$", options: .regularExpression) != nil else { return nil }
        return Bundle.main.url(forResource: key, withExtension: ext, subdirectory: "CommunityMedia")
            ?? Bundle.main.url(forResource: key, withExtension: ext)
    }
}
@MainActor private final class CosmeticLoop {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    init(url: URL) {
        player.isMuted = true; player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)); player.play()
    }
    func stop() { player.pause(); looper?.disableLooping(); looper = nil; player.removeAllItems() }
    deinit { player.pause() }
}
private struct CosmeticVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> CosmeticVideoView { let view = CosmeticVideoView(); view.layerPlayer.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ uiView: CosmeticVideoView, context: Context) { uiView.layerPlayer.player = player }
    static func dismantleUIView(_ uiView: CosmeticVideoView, coordinator: ()) { uiView.layerPlayer.player = nil }
}
private final class CosmeticVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Presentation is fetched separately from inventory and obeys existing profile privacy.
struct CosmeticProfileIdentity: View {
    let profile: UserProfile
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var presentation: CosmeticPresentation?
    @State private var loadedIdentity = ""
    private var identity: String {
        let viewerID: String = session.user?.id ?? "guest"
        let targetID: String = profile.userID
        let profileRevision: String = profile.updatedAt
        var equippedIDs: [String] = []

        if viewerID == targetID, let hub = env.community.hub {
            for item in hub.items {
                if item.equipped {
                    equippedIDs.append(item.id)
                }
            }
        }

        equippedIDs.sort()
        let equipmentRevision: String = equippedIDs.joined(separator: ",")
        let parts: [String] = [viewerID, targetID, profileRevision, equipmentRevision]
        return parts.joined(separator: ":")
    }
    var body: some View {
        VStack(spacing: 16) {
            if loadedIdentity == identity, let banner = presentation?.banner {
                CosmeticMediaView(assetKey: banner.assetKey, posterKey: banner.posterKey, mime: banner.mime, animate: true)
                    .frame(height: 116).clipShape(RoundedRectangle(cornerRadius: 22))
            }
            Group {
                if loadedIdentity == identity, let avatar = presentation?.avatar {
                    CosmeticMediaView(assetKey: avatar.assetKey, posterKey: avatar.posterKey, mime: avatar.mime, animate: true)
                        .frame(width: 112, height: 112).clipShape(Circle())
                } else {
                    ProfileAvatarView(userID: profile.userID, revision: profile.avatarPath ?? profile.updatedAt, size: 112, avatarAvailable: profile.avatarPath != nil)
                }
            }.padding(6).background(Theme.accent.opacity(0.12), in: Circle())
                .overlay { Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1) }
        }.task(id: identity) {
            let key = identity; loadedIdentity = key; presentation = nil
            guard let service = env.communityService, let user = session.user?.id else { return }
            do {
                let value = try await service.presentation(targetId: profile.userID, userId: user)
                guard !Task.isCancelled, key == identity, session.user?.id == user else { return }; presentation = value
            } catch { /* Cosmetics must never block the existing avatar/profile. */ }
        }
    }
}
