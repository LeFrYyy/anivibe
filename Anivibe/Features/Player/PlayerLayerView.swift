import AVKit
import SwiftUI

/// Состояние Picture in Picture для текущего плеера.
@Observable
@MainActor
final class PictureInPictureModel: NSObject, AVPictureInPictureControllerDelegate {
    private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isPossible = false
    private(set) var isActive = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?

    func attach(to layer: AVPlayerLayer) {
        guard isSupported, controller == nil, let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
        possibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            let possible = c.isPictureInPicturePossible
            Task { @MainActor in self?.isPossible = possible }
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() } else { controller.startPictureInPicture() }
    }

    func detach() {
        possibleObservation?.invalidate()
        possibleObservation = nil
        if controller?.isPictureInPictureActive == true { controller?.stopPictureInPicture() }
        controller = nil
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.errorMessage = "Картинка в картинке недоступна: \(error.localizedDescription)" }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // Экран плеера остаётся открытым, пока активен PiP, поэтому восстанавливать нечего.
        completionHandler(true)
    }
}

/// Поверхность видео (AVPlayerLayer) для SwiftUI.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let pip: PictureInPictureModel
    var onTap: (() -> Void)? = nil
    var onHoldBegan: (() -> Void)? = nil
    var onHoldEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.isUserInteractionEnabled = true
        pip.attach(to: view.playerLayer)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.28
        longPress.allowableMovement = .greatestFiniteMagnitude
        tap.require(toFail: longPress)

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        context.coordinator.onTap = onTap
        context.coordinator.onHoldBegan = onHoldBegan
        context.coordinator.onHoldEnded = onHoldEnded
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
        context.coordinator.onTap = onTap
        context.coordinator.onHoldBegan = onHoldBegan
        context.coordinator.onHoldEnded = onHoldEnded
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        uiView.playerLayer.player = nil
        uiView.gestureRecognizers?.forEach { uiView.removeGestureRecognizer($0) }
        coordinator.onTap = nil
        coordinator.onHoldBegan = nil
        coordinator.onHoldEnded = nil
    }

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?
        var onHoldBegan: (() -> Void)?
        var onHoldEnded: (() -> Void)?

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            if sender.state == .ended {
                onTap?()
            }
        }

        @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
            switch sender.state {
            case .began:
                onHoldBegan?()
            case .ended, .cancelled, .failed:
                onHoldEnded?()
            default:
                break
            }
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
