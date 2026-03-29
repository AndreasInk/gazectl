import CoreMotion
import Foundation
import GazectlCore

final class AirPodsTracker: NSObject, HeadTrackingProvider {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let lock = NSLock()

    private var _latestPose: HeadPose?
    private var _sampleCount = 0
    private var _disconnectMessage: String?
    private let smoothing = 0.45

    var source: TrackingSource { .airpods }

    var latestPose: HeadPose? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPose
    }

    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _sampleCount
    }

    var startupIssue: String? {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            return "Motion access denied. Check System Settings -> Privacy & Security -> Motion & Fitness"
        default:
            return "No AirPods motion data received. Connect supported AirPods and rerun."
        }
    }

    var disconnectMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        return _disconnectMessage
    }

    func start(config: Config) throws {
        guard manager.isDeviceMotionAvailable else {
            throw AirPodsTrackerError.deviceMotionUnavailable
        }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            throw AirPodsTrackerError.motionPermissionDenied
        default:
            break
        }

        manager.delegate = self
        if !manager.isConnectionStatusActive {
            manager.startConnectionStatusUpdates()
        }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let attitude = motion.attitude
            let pose = HeadPose(
                yaw: attitude.yaw * 180.0 / .pi,
                pitch: attitude.pitch * 180.0 / .pi,
                roll: attitude.roll * 180.0 / .pi
            )
            self.record(pose: pose)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        if manager.isConnectionStatusActive {
            manager.stopConnectionStatusUpdates()
        }
    }

    func consumeToggleGesture() -> Bool {
        false
    }

    private func record(pose: HeadPose) {
        lock.lock()
        defer { lock.unlock() }

        if let previous = _latestPose {
            _latestPose = HeadPose(
                yaw: previous.yaw + smoothing * (pose.yaw - previous.yaw),
                pitch: previous.pitch + smoothing * (pose.pitch - previous.pitch),
                roll: previous.roll + smoothing * (pose.roll - previous.roll)
            )
        } else {
            _latestPose = pose
        }
        _sampleCount += 1
    }
}

extension AirPodsTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        // Connection is validated by delivered motion samples.
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        lock.lock()
        _disconnectMessage = "AirPods disconnected. Rerun gazectl to capture a fresh session baseline."
        lock.unlock()
    }
}

enum AirPodsTrackerError: Error, CustomStringConvertible {
    case deviceMotionUnavailable
    case motionPermissionDenied

    var description: String {
        switch self {
        case .deviceMotionUnavailable:
            return "AirPods motion tracking is unavailable on this Mac."
        case .motionPermissionDenied:
            return "Motion access denied. Check System Settings -> Privacy & Security -> Motion & Fitness"
        }
    }
}
