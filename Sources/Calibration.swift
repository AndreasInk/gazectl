import Foundation
import GazectlCore

struct ActiveCalibration {
    let poses: [String: HeadPose]
    let anchorMonitorID: String?
}

enum Calibration {
    private static let sampleDuration: TimeInterval = 2.0

    static func loadStore(from path: String) -> CalibrationStore {
        do {
            switch try CalibrationStoreIO.load(from: path) {
            case .missing:
                return CalibrationStore()
            case .loaded(let store):
                return store
            case .migratedLegacyCamera(let store):
                CLI.warning("Migrated legacy camera calibration to the new format")
                saveStore(store, to: path)
                return store
            }
        } catch {
            CLI.warning("Cannot read calibration file: \(error.localizedDescription)")
            return CalibrationStore()
        }
    }

    static func saveStore(_ store: CalibrationStore, to path: String) {
        do {
            try CalibrationStoreIO.save(store, to: path)
            CLI.success("Saved calibration")
        } catch {
            CLI.error("Failed to save calibration: \(error)")
        }
    }

    static func resolveActiveCalibration(
        config: Config,
        tracker: HeadTrackingProvider,
        monitors: [Monitor],
        store: inout CalibrationStore
    ) -> ActiveCalibration? {
        switch config.source {
        case .camera:
            if !config.calibrate, let profile = store.camera {
                CLI.success("Loaded camera calibration")
                return ActiveCalibration(poses: profile.monitors, anchorMonitorID: nil)
            }

            guard let profile = runCameraCalibration(tracker: tracker, monitors: monitors) else {
                return nil
            }
            store.camera = profile
            saveStore(store, to: config.calibrationFile)
            return ActiveCalibration(poses: profile.monitors, anchorMonitorID: nil)

        case .airpods:
            if !config.calibrate, let profile = store.airpods {
                if monitors.contains(where: { String($0.id) == profile.anchorMonitorID }) {
                    if let active = activateAirPodsProfile(profile, tracker: tracker, monitors: monitors) {
                        CLI.success("Loaded AirPods calibration profile")
                        return active
                    }
                    return nil
                }

                CLI.warning("Saved AirPods anchor monitor is unavailable, recalibrating")
            }

            guard let outcome = runAirPodsCalibration(tracker: tracker, monitors: monitors) else {
                return nil
            }
            store.airpods = outcome.profile
            saveStore(store, to: config.calibrationFile)
            return outcome.active
        }
    }

    static func samplePose(
        tracker: HeadTrackingProvider,
        duration: TimeInterval = sampleDuration
    ) -> HeadPose? {
        var yawSamples: [Double] = []
        var pitchSamples: [Double] = []
        var rollSamples: [Double] = []
        let start = Date()
        let expectedSamples = Int(duration / 0.033)

        while Date().timeIntervalSince(start) < duration {
            if let pose = tracker.latestPose {
                yawSamples.append(pose.yaw)
                pitchSamples.append(pose.pitch)
                rollSamples.append(pose.roll)
                CLI.printSamplingProgress(
                    source: tracker.source,
                    pose: pose,
                    sampleCount: yawSamples.count,
                    totalSamples: expectedSamples
                )
            }
            Thread.sleep(forTimeInterval: 0.033)
        }

        print("\(Style.clearLine)\r", terminator: "")
        fflush(stdout)

        guard !yawSamples.isEmpty else { return nil }
        return HeadPose(
            yaw: median(yawSamples),
            pitch: median(pitchSamples),
            roll: median(rollSamples)
        )
    }

    private static func runCameraCalibration(
        tracker: HeadTrackingProvider,
        monitors: [Monitor]
    ) -> CameraCalibrationProfile? {
        CLI.printCalibrationHeader(monitorCount: monitors.count, source: .camera)
        var poses: [String: HeadPose] = [:]

        for (index, monitor) in monitors.enumerated() {
            guard let pose = capturePose(
                tracker: tracker,
                monitor: monitor,
                step: index + 1,
                total: monitors.count,
                prompt: "Look at \(monitor.name), press Enter, and keep looking for 2s"
            ) else {
                return nil
            }
            poses[String(monitor.id)] = pose
            CLI.printCalibrationResult(monitor.name, pose: pose, source: .camera)
        }

        guard poses.count >= 2 else {
            CLI.error("Need at least 2 calibrated monitors.")
            exit(1)
        }

        let entries = sortedEntries(from: poses, monitors: monitors)
        CLI.printCalibrationSummary(entries: entries, source: .camera)
        return CameraCalibrationProfile(monitors: poses)
    }

    private static func runAirPodsCalibration(
        tracker: HeadTrackingProvider,
        monitors: [Monitor]
    ) -> (profile: AirPodsCalibrationProfile, active: ActiveCalibration)? {
        CLI.printCalibrationHeader(monitorCount: monitors.count, source: .airpods)
        guard let anchorMonitor = anchorMonitor(from: monitors) else {
            CLI.error("Need an anchor monitor for AirPods calibration.")
            exit(1)
        }

        CLI.info("AirPods calibration uses \(anchorMonitor.name) as the session anchor.")
        guard let anchorPose = capturePose(
            tracker: tracker,
            monitor: anchorMonitor,
            step: 1,
            total: monitors.count + 1,
            prompt: "Look straight at \(anchorMonitor.name), press Enter, and keep still for 2s to set the anchor baseline"
        ) else {
            return nil
        }
        CLI.printCalibrationResult("\(anchorMonitor.name) (anchor)", pose: anchorPose, source: .airpods)

        var absolutePoses: [String: HeadPose] = [
            String(anchorMonitor.id): anchorPose
        ]

        let remaining = monitors.filter { $0.id != anchorMonitor.id }
        for (index, monitor) in remaining.enumerated() {
            guard let pose = capturePose(
                tracker: tracker,
                monitor: monitor,
                step: index + 2,
                total: monitors.count + 1,
                prompt: "Look at \(monitor.name), press Enter, and keep looking for 2s"
            ) else {
                return nil
            }
            absolutePoses[String(monitor.id)] = pose
            CLI.printCalibrationResult(monitor.name, pose: pose, source: .airpods)
        }

        let profile = AirPodsCalibrationMath.makeProfile(
            anchorMonitorID: String(anchorMonitor.id),
            anchorPose: anchorPose,
            absoluteMonitorPoses: absolutePoses
        )
        let entries = sortedEntries(from: absolutePoses, monitors: monitors)
        CLI.printCalibrationSummary(entries: entries, source: .airpods)
        return (
            profile: profile,
            active: ActiveCalibration(poses: absolutePoses, anchorMonitorID: String(anchorMonitor.id))
        )
    }

    private static func activateAirPodsProfile(
        _ profile: AirPodsCalibrationProfile,
        tracker: HeadTrackingProvider,
        monitors: [Monitor]
    ) -> ActiveCalibration? {
        guard let anchorMonitor = monitors.first(where: { String($0.id) == profile.anchorMonitorID }) else {
            return nil
        }

        CLI.info("Capture a fresh AirPods baseline on \(anchorMonitor.name) for this session.")
        guard let anchorPose = capturePose(
            tracker: tracker,
            monitor: anchorMonitor,
            step: 1,
            total: 1,
            prompt: "Look straight at \(anchorMonitor.name), press Enter, and keep still for 2s to start tracking"
        ) else {
            return nil
        }

        let activePoses = AirPodsCalibrationMath.activateProfile(profile, sessionAnchorPose: anchorPose)
        return ActiveCalibration(poses: activePoses, anchorMonitorID: profile.anchorMonitorID)
    }

    private static func capturePose(
        tracker: HeadTrackingProvider,
        monitor: Monitor,
        step: Int,
        total: Int,
        prompt: String
    ) -> HeadPose? {
        for attempt in 0..<2 {
            ScreenHighlight.show(for: monitor.id)
            CLI.printCalibrationPrompt(prompt, step: step, total: total)
            guard readLine() != nil else {
                ScreenHighlight.hide()
                return nil
            }

            let pose = samplePose(tracker: tracker)
            ScreenHighlight.hide()

            if let pose {
                return pose
            }

            if attempt == 0 {
                CLI.warning("No motion sample detected. Try again.")
            }
        }

        CLI.error("Still no motion sample detected for \(monitor.name).")
        return nil
    }

    private static func anchorMonitor(from monitors: [Monitor]) -> Monitor? {
        if let focusedID = MonitorManager.focusedMonitor(),
           let monitor = monitors.first(where: { $0.id == focusedID }) {
            return monitor
        }

        if let currentID = MonitorManager.currentMonitor(),
           let monitor = monitors.first(where: { $0.id == currentID }) {
            return monitor
        }

        return monitors.first
    }

    private static func sortedEntries(
        from poses: [String: HeadPose],
        monitors: [Monitor]
    ) -> [(name: String, pose: HeadPose)] {
        poses
            .sorted { $0.value.yaw < $1.value.yaw }
            .map { monitorID, pose in
                let name = monitors.first(where: { String($0.id) == monitorID })?.name ?? "?"
                return (name: name, pose: pose)
            }
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
