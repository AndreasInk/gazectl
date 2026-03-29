import Foundation
import GazectlCore

protocol HeadTrackingProvider: AnyObject {
    var source: TrackingSource { get }
    var latestPose: HeadPose? { get }
    var sampleCount: Int { get }
    var startupIssue: String? { get }
    var disconnectMessage: String? { get }

    func start(config: Config) throws
    func stop()
    func consumeToggleGesture() -> Bool
}
