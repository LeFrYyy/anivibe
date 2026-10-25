import AVKit
import SwiftUI
import AnivibeCore

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

/// Gestures belong only to the video surface, never to the controls above it.
@MainActor
struct PlayerSurfaceGestures {
    let tap: @MainActor () -> Void
    let holdBegan: @MainActor () -> Bool
    let holdEnded: @MainActor () -> Void
}

/// Поверхность видео (AVPlayerLayer) для SwiftUI.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let pip: PictureInPictureModel
    let gestures: PlayerSurfaceGestures

    func makeCoordinator() -> Coordinator { Coordinator(gestures: gestures) }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = PlaybackSpeedBoost.activationDelay
        hold.allowableMovement = CGFloat(PlaybackSpeedBoost.allowableMovement)
        hold.numberOfTouchesRequired = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        pip.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.gestures = gestures
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.endHold()
        uiView.playerLayer.player = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var gestures: PlayerSurfaceGestures
        private var holding = false

        init(gestures: PlayerSurfaceGestures) { self.gestures = gestures }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { gestures.tap() }
        }

        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: holding = gestures.holdBegan()
            case .ended, .cancelled, .failed: endHold()
            default: break // Movement after recognition never becomes a seek or tap.
            }
        }

        func endHold() {
            guard holding else { return }
            holding = false
            gestures.holdEnded()
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
