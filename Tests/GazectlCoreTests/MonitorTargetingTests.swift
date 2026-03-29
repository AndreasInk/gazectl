import Testing
@testable import GazectlCore

struct MonitorTargetingTests {
    @Test
    func cameraModeUsesYawAndPitchOnly() {
        let calibration = [
            "1": HeadPose(yaw: -20, pitch: 0, roll: 0),
            "2": HeadPose(yaw: 20, pitch: 0, roll: 0)
        ]

        let target = MonitorTargeting.targetMonitor(
            for: HeadPose(yaw: -18, pitch: 0.5, roll: 90),
            source: .camera,
            calibration: calibration,
            currentMonitor: 2
        )

        #expect(target == 1)
    }

    @Test
    func airPodsModeUsesRollWhenChoosingTarget() {
        let calibration = [
            "1": HeadPose(yaw: 0, pitch: 0, roll: -25),
            "2": HeadPose(yaw: 0, pitch: 0, roll: 25)
        ]

        let target = MonitorTargeting.targetMonitor(
            for: HeadPose(yaw: 0, pitch: 0, roll: 20),
            source: .airpods,
            calibration: calibration,
            currentMonitor: 1
        )

        #expect(target == 2)
    }

    @Test
    func hysteresisPrefersCurrentMonitorNearBoundary() {
        let calibration = [
            "1": HeadPose(yaw: -10, pitch: 0, roll: 0),
            "2": HeadPose(yaw: 10, pitch: 0, roll: 0)
        ]

        let target = MonitorTargeting.targetMonitor(
            for: HeadPose(yaw: 0.5, pitch: 0, roll: 0),
            source: .camera,
            calibration: calibration,
            currentMonitor: 1,
            hysteresis: 0.25
        )

        #expect(target == 1)
    }
}
