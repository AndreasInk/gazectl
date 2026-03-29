import Foundation

public enum AirPodsStabilityReason: String, Equatable, Sendable {
    case sameMonitor = "same_monitor"
    case insufficientMargin = "insufficient_margin"
    case candidateStarted = "candidate_started"
    case dwelling = "dwelling"
    case cooldown = "cooldown"
    case committed = "committed"
}

public struct AirPodsStabilityProfile: Equatable, Sendable {
    public var trackingPollInterval: TimeInterval
    public var switchCooldown: TimeInterval
    public var candidateDwell: TimeInterval
    public var improvementMargin: Double

    public init(
        trackingPollInterval: TimeInterval = 0.016,
        switchCooldown: TimeInterval = 0.30,
        candidateDwell: TimeInterval = 0.10,
        improvementMargin: Double = 0.04
    ) {
        self.trackingPollInterval = trackingPollInterval
        self.switchCooldown = switchCooldown
        self.candidateDwell = candidateDwell
        self.improvementMargin = improvementMargin
    }
}

public struct AirPodsStabilityState: Equatable, Sendable {
    public var candidateMonitor: Int?
    public var candidateSince: TimeInterval?
    public var lastCommittedSwitchTime: TimeInterval?

    public init(
        candidateMonitor: Int? = nil,
        candidateSince: TimeInterval? = nil,
        lastCommittedSwitchTime: TimeInterval? = nil
    ) {
        self.candidateMonitor = candidateMonitor
        self.candidateSince = candidateSince
        self.lastCommittedSwitchTime = lastCommittedSwitchTime
    }
}

public struct AirPodsStabilityStep: Equatable, Sendable {
    public let committedMonitor: Int
    public let state: AirPodsStabilityState
    public let isSwitchCommitted: Bool
    public let reason: AirPodsStabilityReason

    public init(
        committedMonitor: Int,
        state: AirPodsStabilityState,
        isSwitchCommitted: Bool,
        reason: AirPodsStabilityReason
    ) {
        self.committedMonitor = committedMonitor
        self.state = state
        self.isSwitchCommitted = isSwitchCommitted
        self.reason = reason
    }
}

public enum AirPodsStabilityFilter {
    public static func step(
        currentMonitor: Int,
        decision: MonitorTargetDecision,
        state: AirPodsStabilityState,
        now: TimeInterval,
        profile: AirPodsStabilityProfile = AirPodsStabilityProfile()
    ) -> AirPodsStabilityStep {
        var nextState = state

        if decision.bestMonitor == currentMonitor {
            nextState.candidateMonitor = nil
            nextState.candidateSince = nil
            return AirPodsStabilityStep(
                committedMonitor: currentMonitor,
                state: nextState,
                isSwitchCommitted: false,
                reason: .sameMonitor
            )
        }

        guard decision.improvementMargin >= profile.improvementMargin else {
            nextState.candidateMonitor = nil
            nextState.candidateSince = nil
            return AirPodsStabilityStep(
                committedMonitor: currentMonitor,
                state: nextState,
                isSwitchCommitted: false,
                reason: .insufficientMargin
            )
        }

        if nextState.candidateMonitor != decision.bestMonitor {
            nextState.candidateMonitor = decision.bestMonitor
            nextState.candidateSince = now
            return AirPodsStabilityStep(
                committedMonitor: currentMonitor,
                state: nextState,
                isSwitchCommitted: false,
                reason: .candidateStarted
            )
        }

        guard let candidateSince = nextState.candidateSince,
              now - candidateSince >= profile.candidateDwell else {
            return AirPodsStabilityStep(
                committedMonitor: currentMonitor,
                state: nextState,
                isSwitchCommitted: false,
                reason: .dwelling
            )
        }

        let lastCommitted = nextState.lastCommittedSwitchTime ?? -.infinity
        guard now - lastCommitted >= profile.switchCooldown else {
            return AirPodsStabilityStep(
                committedMonitor: currentMonitor,
                state: nextState,
                isSwitchCommitted: false,
                reason: .cooldown
            )
        }

        nextState.candidateMonitor = nil
        nextState.candidateSince = nil
        return AirPodsStabilityStep(
            committedMonitor: decision.bestMonitor,
            state: nextState,
            isSwitchCommitted: true,
            reason: .committed
        )
    }
}
