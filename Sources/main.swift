import Foundation
import CoreGraphics
import GazectlCore

// MARK: - Signal handling

var running = true

func handleSignal(_: Int32) {
    running = false
}

signal(SIGINT, handleSignal)
signal(SIGTERM, handleSignal)

// MARK: - Main

func tracker(for source: TrackingSource) -> HeadTrackingProvider {
    switch source {
    case .camera:
        return FaceTracker()
    case .airpods:
        return AirPodsTracker()
    }
}

func waitForSamples(from tracker: HeadTrackingProvider, timeout: TimeInterval) -> Bool {
    let initialSamples = tracker.sampleCount
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if tracker.sampleCount > initialSamples {
            return true
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return false
}

func run(config: Config) -> Int32 {
    CLI.printBanner()

    let monitorSpinner = CLI.Spinner("Detecting monitors…")
    monitorSpinner.start()

    let monitors = MonitorManager.listMonitors()
    guard monitors.count >= 2 else {
        monitorSpinner.fail(finalMessage: "Need at least 2 monitors (found \(monitors.count))")
        return 1
    }
    monitorSpinner.stop(finalMessage: "Found \(monitors.count) monitors")

    let tracker = tracker(for: config.source)
    let startupSpinner = CLI.Spinner("Starting \(config.source.displayName.lowercased()) tracking…")
    startupSpinner.start()

    do {
        try tracker.start(config: config)
    } catch {
        startupSpinner.fail(finalMessage: String(describing: error))
        return 1
    }

    let ready = waitForSamples(
        from: tracker,
        timeout: config.source == .camera ? 2.0 : 3.0
    )
    guard ready else {
        startupSpinner.fail(finalMessage: tracker.startupIssue ?? "Tracking failed to start")
        if config.source == .camera {
            CLI.info("Check System Settings -> Privacy & Security -> Camera")
        }
        tracker.stop()
        return 1
    }
    startupSpinner.stop(finalMessage: "\(config.source.displayName) ready")

    var store = Calibration.loadStore(from: config.calibrationFile)
    guard let activeCalibration = Calibration.resolveActiveCalibration(
        config: config,
        tracker: tracker,
        monitors: monitors,
        store: &store
    ) else {
        tracker.stop()
        CLI.printExit()
        return 0
    }

    let sortedCalibration = activeCalibration.poses.sorted { $0.value.yaw < $1.value.yaw }
    let monitorSummary: [(name: String, pose: HeadPose)] = sortedCalibration.map { monitorID, pose in
        let name = monitors.first(where: { String($0.id) == monitorID })?.name ?? "?"
        return (name: name, pose: pose)
    }

    let boundaries = config.source == .camera
        ? MonitorTargeting.cameraYawBoundaries(from: activeCalibration.poses)
        : []
    let anchorName = activeCalibration.anchorMonitorID.flatMap { anchorID in
        monitors.first(where: { String($0.id) == anchorID })?.name
    }

    CLI.printStartupSummary(
        source: config.source,
        monitors: monitorSummary,
        boundaries: boundaries,
        verbose: config.verbose,
        anchorName: anchorName
    )

    var gazeMonitor = MonitorManager.focusedMonitor() ?? MonitorManager.currentMonitor()
    var lastAppliedMonitor = gazeMonitor
    var lastSwitchTime = Date.distantPast
    let airPodsProfile = config.source == .airpods ? AirPodsStabilityProfile() : nil
    let trackingPollInterval = airPodsProfile?.trackingPollInterval ?? 0.033
    var airPodsState = AirPodsStabilityState()
    var lastAirPodsDebugLogTime = Date.distantPast
    var trackingEnabled = true
    var exitCode: Int32 = 0

    while running {
        if let disconnectMessage = tracker.disconnectMessage {
            CLI.error(disconnectMessage)
            exitCode = 1
            break
        }

        if config.source.supportsToggleGesture, tracker.consumeToggleGesture() {
            trackingEnabled.toggle()
            CLI.printTrackingToggled(enabled: trackingEnabled)
            if trackingEnabled {
                gazeMonitor = MonitorManager.focusedMonitor() ?? MonitorManager.currentMonitor()
                lastAppliedMonitor = gazeMonitor
            }
        }

        if trackingEnabled, let pose = tracker.latestPose {
            let cursorMonitor = MonitorManager.currentMonitor()
            let decision = MonitorTargeting.targetDecision(
                for: pose,
                source: config.source,
                calibration: activeCalibration.poses,
                currentMonitor: gazeMonitor ?? 0
            )
            let rawTarget = decision.bestMonitor
            let now = Date()
            var airPodsFilterStep: AirPodsStabilityStep?

            if let airPodsProfile {
                let filterStep = AirPodsStabilityFilter.step(
                    currentMonitor: lastAppliedMonitor ?? rawTarget,
                    decision: decision,
                    state: airPodsState,
                    now: now.timeIntervalSinceReferenceDate,
                    profile: airPodsProfile
                )
                airPodsFilterStep = filterStep
                airPodsState = filterStep.state
                gazeMonitor = filterStep.committedMonitor
            } else {
                gazeMonitor = rawTarget
            }

            if config.verbose {
                let targetName = monitors.first(where: { $0.id == rawTarget })?.name ?? "?"
                CLI.printTrackingStatus(source: config.source, pose: pose, targetName: targetName)
            }

            if gazeMonitor != lastAppliedMonitor {
                let target = gazeMonitor ?? rawTarget
                let transition = MonitorManager.transition(to: target, cursorMonitor: cursorMonitor)

                if config.debug {
                    let targetName = monitors.first(where: { $0.id == target })?.name ?? "?"
                    let rawTargetName = monitors.first(where: { $0.id == rawTarget })?.name ?? "?"
                    let cursorName = cursorMonitor.flatMap { current in monitors.first(where: { $0.id == current })?.name } ?? "nil"
                    let axMonitor = MonitorManager.focusedMonitor()
                    let axName = axMonitor.flatMap { current in monitors.first(where: { $0.id == current })?.name } ?? "nil"
                    let candidateName = airPodsState.candidateMonitor.flatMap { candidate in
                        monitors.first(where: { $0.id == candidate })?.name
                    } ?? "nil"
                    let dwellProgress: String
                    if let airPodsProfile, let candidateSince = airPodsState.candidateSince {
                        dwellProgress = String(format: "%.2f/%.2fs", now.timeIntervalSinceReferenceDate - candidateSince, airPodsProfile.candidateDwell)
                    } else {
                        dwellProgress = "n/a"
                    }
                    CLI.debug("""
                    [TRANSITION] source=\(config.source.rawValue) raw=\(rawTargetName) committed=\(targetName) pose=(yaw:\(String(format: "%.1f", pose.yaw)) pitch:\(String(format: "%.1f", pose.pitch)) roll:\(String(format: "%.1f", pose.roll))) margin=\(String(format: "%.2f", decision.improvementMargin)) candidate=\(candidateName) dwell=\(dwellProgress) \
                    cursor=\(cursorName) (id:\(cursorMonitor.map(String.init) ?? "nil")) \
                    ax=\(axName) (id:\(axMonitor.map(String.init) ?? "nil")) \
                    → \(transition)
                    """)
                }

                if transition.requiresAction {
                    let switchCooldown = airPodsProfile?.switchCooldown ?? 0.5
                    let elapsedSinceLastCommit: TimeInterval
                    if airPodsProfile == nil {
                        elapsedSinceLastCommit = now.timeIntervalSince(lastSwitchTime)
                    } else {
                        let lastCommitTime = airPodsState.lastCommittedSwitchTime ?? -.infinity
                        elapsedSinceLastCommit = now.timeIntervalSinceReferenceDate - lastCommitTime
                    }
                    if elapsedSinceLastCommit >= switchCooldown {
                        let name = monitors.first(where: { $0.id == target })?.name ?? "?"
                        MonitorManager.focusMonitor(target, transition: transition, debug: config.debug)
                        lastAppliedMonitor = target
                        if airPodsProfile == nil {
                            lastSwitchTime = now
                        } else {
                            airPodsState.lastCommittedSwitchTime = now.timeIntervalSinceReferenceDate
                            airPodsState.candidateMonitor = nil
                            airPodsState.candidateSince = nil
                        }
                        CLI.printFocusSwitch(name)
                    } else if config.debug {
                        CLI.debug("[COOLDOWN] \(String(format: "%.2f", elapsedSinceLastCommit))s < \(switchCooldown)s — skipped")
                    }
                } else {
                    if config.debug {
                        CLI.debug("[NO-ACTION] transition=\(transition), updating lastApplied without action")
                    }
                    lastAppliedMonitor = target
                    if airPodsProfile != nil {
                        airPodsState.candidateMonitor = nil
                        airPodsState.candidateSince = nil
                    }
                }
            } else if config.source == .airpods, config.debug {
                let rawTargetName = monitors.first(where: { $0.id == rawTarget })?.name ?? "?"
                let committedName = lastAppliedMonitor.flatMap { monitorID in
                    monitors.first(where: { $0.id == monitorID })?.name
                } ?? "nil"
                let candidateName = airPodsState.candidateMonitor.flatMap { candidate in
                    monitors.first(where: { $0.id == candidate })?.name
                } ?? "nil"
                let dwellProgress: String
                if let airPodsProfile, let candidateSince = airPodsState.candidateSince {
                    dwellProgress = String(format: "%.2f/%.2fs", now.timeIntervalSinceReferenceDate - candidateSince, airPodsProfile.candidateDwell)
                } else {
                    dwellProgress = "n/a"
                }
                let gateReason = airPodsFilterStep?.reason.rawValue ?? "n/a"
                CLI.debug(
                    "[AIRPODS] raw=\(rawTargetName) committed=\(committedName) best=\(String(format: "%.2f", decision.bestDistance)) current=\(String(format: "%.2f", decision.currentMonitorDistance)) margin=\(String(format: "%.2f", decision.improvementMargin)) gate=\(gateReason) candidate=\(candidateName) dwell=\(dwellProgress)"
                )

                if now.timeIntervalSince(lastAirPodsDebugLogTime) >= 0.25 {
                    lastAirPodsDebugLogTime = now
                    let scores = MonitorTargeting.debugScores(
                        for: pose,
                        source: config.source,
                        calibration: activeCalibration.poses,
                        currentMonitor: lastAppliedMonitor ?? rawTarget
                    )
                    let scoreSummary = scores.prefix(4).map { score in
                        let name = monitors.first(where: { $0.id == score.monitorID })?.name ?? String(score.monitorID)
                        return "\(name){raw:\(String(format: "%.2f", score.rawDistance)) eff:\(String(format: "%.2f", score.effectiveDistance)) dy:\(String(format: "%.2f", score.normalizedYawDelta)) dp:\(String(format: "%.2f", score.normalizedPitchDelta)) dr:\(String(format: "%.2f", score.normalizedRollDelta))\(score.isCurrentMonitor ? " current" : "")}"
                    }.joined(separator: " | ")
                    CLI.debug("[AIRPODS-SCORES] \(scoreSummary)")
                }
            }
        }

        Thread.sleep(forTimeInterval: trackingPollInterval)
    }

    tracker.stop()
    CLI.printExit()
    return exitCode
}

let parsedCommand: ParsedCommand
do {
    parsedCommand = try ConfigParser.parse(arguments: CommandLine.arguments)
} catch let error as ConfigParseError {
    CLI.error(error.description)
    CLI.printUsage()
    exit(1)
} catch {
    CLI.error(error.localizedDescription)
    exit(1)
}

switch parsedCommand {
case .help:
    CLI.printUsage()
    exit(0)
case .version:
    CLI.printVersion()
    exit(0)
case .run(let config):
    exit(run(config: config))
}
