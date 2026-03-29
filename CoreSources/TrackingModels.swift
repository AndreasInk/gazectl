import Foundation

public enum TrackingSource: String, Codable, CaseIterable, Sendable {
    case camera
    case airpods

    public var displayName: String {
        switch self {
        case .camera:
            return "Camera"
        case .airpods:
            return "AirPods"
        }
    }

    public var activeAxes: [PoseAxis] {
        switch self {
        case .camera:
            return [.yaw, .pitch]
        case .airpods:
            return PoseAxis.allCases
        }
    }

    public var supportsToggleGesture: Bool {
        self == .camera
    }
}

public enum PoseAxis: CaseIterable, Sendable {
    case yaw
    case pitch
    case roll
}

public struct HeadPose: Codable, Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double = 0) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let zero = HeadPose(yaw: 0, pitch: 0, roll: 0)

    public func value(for axis: PoseAxis) -> Double {
        switch axis {
        case .yaw:
            return yaw
        case .pitch:
            return pitch
        case .roll:
            return roll
        }
    }

    public func adding(_ other: HeadPose) -> HeadPose {
        HeadPose(
            yaw: yaw + other.yaw,
            pitch: pitch + other.pitch,
            roll: roll + other.roll
        )
    }

    public func subtracting(_ other: HeadPose) -> HeadPose {
        HeadPose(
            yaw: yaw - other.yaw,
            pitch: pitch - other.pitch,
            roll: roll - other.roll
        )
    }
}

public struct PoseSpread: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public func value(for axis: PoseAxis) -> Double {
        switch axis {
        case .yaw:
            return yaw
        case .pitch:
            return pitch
        case .roll:
            return roll
        }
    }
}
