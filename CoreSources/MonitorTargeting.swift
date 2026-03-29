import Foundation

public struct MonitorTargetDecision: Equatable, Sendable {
    public let bestMonitor: Int
    public let bestDistance: Double
    public let currentMonitorDistance: Double
    public let secondBestDistance: Double

    public init(
        bestMonitor: Int,
        bestDistance: Double,
        currentMonitorDistance: Double,
        secondBestDistance: Double
    ) {
        self.bestMonitor = bestMonitor
        self.bestDistance = bestDistance
        self.currentMonitorDistance = currentMonitorDistance
        self.secondBestDistance = secondBestDistance
    }

    public var improvementMargin: Double {
        currentMonitorDistance - bestDistance
    }
}

public struct MonitorTargetDebugScore: Equatable, Sendable {
    public let monitorID: Int
    public let rawDistance: Double
    public let effectiveDistance: Double
    public let normalizedYawDelta: Double
    public let normalizedPitchDelta: Double
    public let normalizedRollDelta: Double
    public let isCurrentMonitor: Bool

    public init(
        monitorID: Int,
        rawDistance: Double,
        effectiveDistance: Double,
        normalizedYawDelta: Double,
        normalizedPitchDelta: Double,
        normalizedRollDelta: Double,
        isCurrentMonitor: Bool
    ) {
        self.monitorID = monitorID
        self.rawDistance = rawDistance
        self.effectiveDistance = effectiveDistance
        self.normalizedYawDelta = normalizedYawDelta
        self.normalizedPitchDelta = normalizedPitchDelta
        self.normalizedRollDelta = normalizedRollDelta
        self.isCurrentMonitor = isCurrentMonitor
    }
}

public enum MonitorTargeting {
    private static let minimumSpread = 1.0

    public static func targetDecision(
        for pose: HeadPose,
        source: TrackingSource,
        calibration: [String: HeadPose],
        currentMonitor: Int = 0,
        hysteresis: Double? = nil
    ) -> MonitorTargetDecision {
        guard !calibration.isEmpty else {
            return MonitorTargetDecision(
                bestMonitor: 0,
                bestDistance: .infinity,
                currentMonitorDistance: .infinity,
                secondBestDistance: .infinity
            )
        }

        let spreads = spreads(for: calibration, source: source)
        let currentKey = String(currentMonitor)
        let effectiveHysteresis = hysteresis ?? defaultHysteresis(for: source)
        var bestMonitor = 0
        var bestDistance = Double.infinity
        var secondBestDistance = Double.infinity
        var currentMonitorDistance = Double.infinity

        for (key, calibratedPose) in calibration {
            let rawDistance = normalizedDistance(
                from: pose,
                to: calibratedPose,
                source: source,
                spreads: spreads
            )
            var distance = rawDistance

            if key == currentKey {
                currentMonitorDistance = rawDistance
            }

            if key == currentKey {
                distance *= (1.0 - effectiveHysteresis)
            }

            if distance < bestDistance {
                secondBestDistance = bestDistance
                bestDistance = distance
                bestMonitor = Int(key) ?? 0
            } else if distance < secondBestDistance {
                secondBestDistance = distance
            }
        }

        if currentMonitorDistance.isInfinite {
            currentMonitorDistance = bestDistance
        }

        return MonitorTargetDecision(
            bestMonitor: bestMonitor,
            bestDistance: bestDistance,
            currentMonitorDistance: currentMonitorDistance,
            secondBestDistance: secondBestDistance
        )
    }

    public static func targetMonitor(
        for pose: HeadPose,
        source: TrackingSource,
        calibration: [String: HeadPose],
        currentMonitor: Int = 0,
        hysteresis: Double? = nil
    ) -> Int {
        targetDecision(
            for: pose,
            source: source,
            calibration: calibration,
            currentMonitor: currentMonitor,
            hysteresis: hysteresis
        ).bestMonitor
    }

    public static func debugScores(
        for pose: HeadPose,
        source: TrackingSource,
        calibration: [String: HeadPose],
        currentMonitor: Int = 0,
        hysteresis: Double? = nil
    ) -> [MonitorTargetDebugScore] {
        guard !calibration.isEmpty else { return [] }

        let spreads = spreads(for: calibration, source: source)
        let effectiveHysteresis = hysteresis ?? defaultHysteresis(for: source)
        let currentKey = String(currentMonitor)

        return calibration.compactMap { key, targetPose in
            let monitorID = Int(key) ?? 0
            let normalizedYawDelta = normalizedDelta(
                pose.value(for: .yaw) - targetPose.value(for: .yaw),
                spread: spreads.yaw
            )
            let normalizedPitchDelta = normalizedDelta(
                pose.value(for: .pitch) - targetPose.value(for: .pitch),
                spread: spreads.pitch
            )
            let normalizedRollDelta = normalizedDelta(
                pose.value(for: .roll) - targetPose.value(for: .roll),
                spread: spreads.roll
            )

            let rawDistance = normalizedDistance(
                from: pose,
                to: targetPose,
                source: source,
                spreads: spreads
            )
            let isCurrentMonitor = key == currentKey
            let effectiveDistance = isCurrentMonitor
                ? rawDistance * (1.0 - effectiveHysteresis)
                : rawDistance

            return MonitorTargetDebugScore(
                monitorID: monitorID,
                rawDistance: rawDistance,
                effectiveDistance: effectiveDistance,
                normalizedYawDelta: normalizedYawDelta,
                normalizedPitchDelta: normalizedPitchDelta,
                normalizedRollDelta: normalizedRollDelta,
                isCurrentMonitor: isCurrentMonitor
            )
        }
        .sorted { lhs, rhs in
            lhs.effectiveDistance < rhs.effectiveDistance
        }
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

    private static func normalizedDelta(_ delta: Double, spread: Double) -> Double {
        delta / spread
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
            return 0.15
        }
    }
}
