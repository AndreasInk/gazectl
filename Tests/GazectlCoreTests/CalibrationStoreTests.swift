import Foundation
import Testing
@testable import GazectlCore

struct CalibrationStoreTests {
    @Test
    func migratesLegacyCameraCalibration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("calibration.json")

        let legacy = """
        {
          "101": { "yaw": -18.5, "pitch": 1.2 },
          "202": { "yaw": 16.0, "pitch": -0.7 }
        }
        """
        try legacy.data(using: .utf8)?.write(to: fileURL)

        let result = try CalibrationStoreIO.load(from: fileURL.path)

        guard case .migratedLegacyCamera(let store) = result else {
            Issue.record("Expected legacy migration")
            return
        }

        #expect(store.camera?.monitors["101"] == HeadPose(yaw: -18.5, pitch: 1.2, roll: 0))
        #expect(store.airpods == nil)
    }

    @Test
    func savesAndLoadsVersionedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("calibration.json")

        let store = CalibrationStore(
            camera: CameraCalibrationProfile(monitors: [
                "1": HeadPose(yaw: -10, pitch: 0, roll: 0)
            ]),
            airpods: AirPodsCalibrationProfile(
                anchorMonitorID: "1",
                relativeMonitors: [
                    "1": .zero,
                    "2": HeadPose(yaw: 28, pitch: 4, roll: -3)
                ]
            )
        )

        try CalibrationStoreIO.save(store, to: fileURL.path)
        let loaded = try CalibrationStoreIO.load(from: fileURL.path)

        #expect(loaded == .loaded(store))
    }

    @Test
    func activatesAirPodsProfileAgainstFreshBaseline() {
        let profile = AirPodsCalibrationProfile(
            anchorMonitorID: "10",
            relativeMonitors: [
                "10": .zero,
                "20": HeadPose(yaw: 25, pitch: 3, roll: -2)
            ]
        )

        let active = AirPodsCalibrationMath.activateProfile(
            profile,
            sessionAnchorPose: HeadPose(yaw: 4, pitch: -1, roll: 6)
        )

        #expect(active["10"] == HeadPose(yaw: 4, pitch: -1, roll: 6))
        #expect(active["20"] == HeadPose(yaw: 29, pitch: 2, roll: 4))
    }
}
