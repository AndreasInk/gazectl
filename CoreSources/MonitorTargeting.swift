import Foundation

public enum MonitorTargeting {
    private static let minimumSpread = 1.0

    public static func targetMonitor(
        for pose: HeadPose,
        source: TrackingSource,
        calibration: [String: HeadPose],
        currentMonitor: Int = 0,
        hysteresis: Double? = nil
    ) -> Int {
        guard !calibration.isEmpty else { return 0 }

        let spreads = spreads(for: calibration, source: source)
        let currentKey = String(currentMonitor)
        let effectiveHysteresis = hysteresis ?? defaultHysteresis(for: source)
        var bestMonitor = 0
        var bestDistance = Double.infinity

        for (key, calibratedPose) in calibration {
            var distance = normalizedDistance(
                from: pose,
                to: calibratedPose,
                source: source,
                spreads: spreads
            )

            if key == currentKey {
                distance *= (1.0 - effectiveHysteresis)
            }

            if distance < bestDistance {
                bestDistance = distance
                bestMonitor = Int(key) ?? 0
            }
        }

        return bestMonitor
    }

    public static func normalizedDistance(
        from pose: HeadPose,
        to target: HeadPose,
        source: TrackingSource,
        spreads: PoseSpread
    ) -> Double {
        let squared = source.activeAxes.reduce(0.0) { total, axis in
            let delta = pose.value(for: axis) - target.value(for: axis)
            let spread = spreads.value(for: axis)
            return total + pow(delta / spread, 2)
        }
        return sqrt(squared)
    }

    public static func spreads(
        for calibration: [String: HeadPose],
        source: TrackingSource
    ) -> PoseSpread {
        func spread(for axis: PoseAxis) -> Double {
            let values = calibration.values.map { $0.value(for: axis) }
            guard let minimum = values.min(), let maximum = values.max() else {
                return minimumSpread
            }
            return Swift.max(maximum - minimum, minimumSpread)
        }

        let yaw = spread(for: .yaw)
        let pitch = source.activeAxes.contains(.pitch) ? spread(for: .pitch) : minimumSpread
        let roll = source.activeAxes.contains(.roll) ? spread(for: .roll) : minimumSpread
        return PoseSpread(yaw: yaw, pitch: pitch, roll: roll)
    }

    public static func cameraYawBoundaries(from calibration: [String: HeadPose]) -> [Double] {
        let sorted = calibration.sorted { $0.value.yaw < $1.value.yaw }
        guard sorted.count > 1 else { return [] }
        return (0..<(sorted.count - 1)).map { index in
            (sorted[index].value.yaw + sorted[index + 1].value.yaw) / 2.0
        }
    }

    private static func defaultHysteresis(for source: TrackingSource) -> Double {
        switch source {
        case .camera:
            return 0.25
        case .airpods:
            return 0.12
        }
    }
}
