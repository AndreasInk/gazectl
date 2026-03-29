import Foundation

public struct CameraCalibrationProfile: Codable, Equatable, Sendable {
    public var monitors: [String: HeadPose]

    public init(monitors: [String: HeadPose]) {
        self.monitors = monitors
    }
}

public struct AirPodsCalibrationProfile: Codable, Equatable, Sendable {
    public var anchorMonitorID: String
    public var relativeMonitors: [String: HeadPose]

    public init(anchorMonitorID: String, relativeMonitors: [String: HeadPose]) {
        self.anchorMonitorID = anchorMonitorID
        self.relativeMonitors = relativeMonitors
    }
}

public struct CalibrationStore: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var camera: CameraCalibrationProfile?
    public var airpods: AirPodsCalibrationProfile?

    public init(
        version: Int = CalibrationStore.currentVersion,
        camera: CameraCalibrationProfile? = nil,
        airpods: AirPodsCalibrationProfile? = nil
    ) {
        self.version = version
        self.camera = camera
        self.airpods = airpods
    }
}

public enum CalibrationStoreLoadResult: Equatable, Sendable {
    case missing
    case loaded(CalibrationStore)
    case migratedLegacyCamera(CalibrationStore)
}

public enum CalibrationStoreIO {
    public static func load(from path: String) throws -> CalibrationStoreLoadResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .missing
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        if let store = try? decoder.decode(CalibrationStore.self, from: data) {
            return .loaded(store)
        }

        if let legacyProfile = migrateLegacyCameraProfile(from: data) {
            return .migratedLegacyCamera(CalibrationStore(camera: legacyProfile))
        }

        throw NSError(domain: "GazectlCore.CalibrationStoreIO", code: 1)
    }

    public static func save(_ store: CalibrationStore, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func migrateLegacyCameraProfile(from data: Data) -> CameraCalibrationProfile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var migrated: [String: HeadPose] = [:]
        for (key, value) in object {
            guard let monitor = value as? [String: Any],
                  let yaw = monitor["yaw"] as? Double else {
                return nil
            }
            let pitch = monitor["pitch"] as? Double ?? 0
            migrated[key] = HeadPose(yaw: yaw, pitch: pitch, roll: 0)
        }

        return migrated.isEmpty ? nil : CameraCalibrationProfile(monitors: migrated)
    }
}

public enum AirPodsCalibrationMath {
    public static func makeProfile(
        anchorMonitorID: String,
        anchorPose: HeadPose,
        absoluteMonitorPoses: [String: HeadPose]
    ) -> AirPodsCalibrationProfile {
        let relativeMonitors = absoluteMonitorPoses.mapValues { $0.subtracting(anchorPose) }
        return AirPodsCalibrationProfile(
            anchorMonitorID: anchorMonitorID,
            relativeMonitors: relativeMonitors
        )
    }

    public static func activateProfile(
        _ profile: AirPodsCalibrationProfile,
        sessionAnchorPose: HeadPose
    ) -> [String: HeadPose] {
        profile.relativeMonitors.mapValues { $0.adding(sessionAnchorPose) }
    }
}
