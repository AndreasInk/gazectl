import Testing
@testable import GazectlCore

struct MonitorTargetingTests {
    @Test
    func targetDecisionReportsDistanceMetadata() {
        let calibration = [
            "1": HeadPose(yaw: -20, pitch: 0, roll: 0),
            "2": HeadPose(yaw: 20, pitch: 0, roll: 0)
        ]

        let decision = MonitorTargeting.targetDecision(
            for: HeadPose(yaw: -18, pitch: 0, roll: 0),
            source: .camera,
            calibration: calibration,
            currentMonitor: 2
        )

        #expect(decision.bestMonitor == 1)
        #expect(decision.bestDistance < decision.currentMonitorDistance)
        #expect(decision.secondBestDistance >= decision.bestDistance)
    }

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

struct AirPodsStabilityFilterTests {
    private let profile = AirPodsStabilityProfile(
        switchCooldown: 0.30,
        candidateDwell: 0.18,
        improvementMargin: 0.12
    )

    @Test
    func briefJitterDoesNotSwitch() {
        let decision = MonitorTargetDecision(
            bestMonitor: 2,
            bestDistance: 0.30,
            currentMonitorDistance: 0.50,
            secondBestDistance: 0.55
        )

        let first = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: decision,
            state: AirPodsStabilityState(),
            now: 1.00,
            profile: profile
        )
        let second = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: decision,
            state: first.state,
            now: 1.10,
            profile: profile
        )

        #expect(first.committedMonitor == 1)
        #expect(second.committedMonitor == 1)
        #expect(second.isSwitchCommitted == false)
    }

    @Test
    func sustainedLeadCommitsAfterDwell() {
        let decision = MonitorTargetDecision(
            bestMonitor: 2,
            bestDistance: 0.20,
            currentMonitorDistance: 0.45,
            secondBestDistance: 0.60
        )

        let first = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: decision,
            state: AirPodsStabilityState(),
            now: 1.00,
            profile: profile
        )
        let second = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: decision,
            state: first.state,
            now: 1.19,
            profile: profile
        )

        #expect(second.committedMonitor == 2)
        #expect(second.isSwitchCommitted)
    }

    @Test
    func tinyMarginDoesNotArmCandidate() {
        let decision = MonitorTargetDecision(
            bestMonitor: 2,
            bestDistance: 0.30,
            currentMonitorDistance: 0.38,
            secondBestDistance: 0.42
        )

        let step = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: decision,
            state: AirPodsStabilityState(),
            now: 1.00,
            profile: profile
        )

        #expect(step.committedMonitor == 1)
        #expect(step.state.candidateMonitor == nil)
    }

    @Test
    func candidateResetsWhenRawTargetChanges() {
        let firstDecision = MonitorTargetDecision(
            bestMonitor: 2,
            bestDistance: 0.20,
            currentMonitorDistance: 0.50,
            secondBestDistance: 0.60
        )
        let secondDecision = MonitorTargetDecision(
            bestMonitor: 3,
            bestDistance: 0.18,
            currentMonitorDistance: 0.52,
            secondBestDistance: 0.58
        )

        let first = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: firstDecision,
            state: AirPodsStabilityState(),
            now: 1.00,
            profile: profile
        )
        let second = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: secondDecision,
            state: first.state,
            now: 1.05,
            profile: profile
        )

        #expect(second.committedMonitor == 1)
        #expect(second.state.candidateMonitor == 3)
        #expect(second.state.candidateSince == 1.05)
    }

    @Test
    func cooldownPreventsImmediateBounceBack() {
        let switchToTwo = MonitorTargetDecision(
            bestMonitor: 2,
            bestDistance: 0.20,
            currentMonitorDistance: 0.50,
            secondBestDistance: 0.60
        )
        let bounceBack = MonitorTargetDecision(
            bestMonitor: 1,
            bestDistance: 0.18,
            currentMonitorDistance: 0.44,
            secondBestDistance: 0.62
        )

        let first = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: switchToTwo,
            state: AirPodsStabilityState(),
            now: 1.00,
            profile: profile
        )
        let committed = AirPodsStabilityFilter.step(
            currentMonitor: 1,
            decision: switchToTwo,
            state: first.state,
            now: 1.19,
            profile: profile
        )
        let rebound = AirPodsStabilityFilter.step(
            currentMonitor: 2,
            decision: bounceBack,
            state: committed.state,
            now: 1.30,
            profile: profile
        )

        #expect(committed.committedMonitor == 2)
        #expect(rebound.committedMonitor == 2)
        #expect(rebound.isSwitchCommitted == false)
    }
}
