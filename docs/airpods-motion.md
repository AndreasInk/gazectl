# AirPods Motion Model

`gazectl --source airpods` uses `CMHeadphoneMotionManager` on macOS 14+.

## Why calibration is session-relative

AirPods attitude is reported relative to the current Core Motion session, not as a stable absolute orientation you can safely reuse across launches. Reusing raw saved yaw/pitch/roll values across launches would drift and cause wrong monitor switches.

## Stored calibration

The calibration file now stores a versioned source-aware payload:

- `camera`: absolute per-monitor yaw/pitch poses
- `airpods`: per-monitor pose deltas relative to one anchor monitor

The AirPods profile stores:

- the anchor monitor ID
- relative yaw/pitch/roll deltas from that anchor to each monitor

## Startup flow for AirPods

At runtime, `gazectl` asks for a short baseline on the saved anchor monitor. That live anchor pose is combined with the saved relative deltas to reconstruct the active per-monitor poses for the current session.

This keeps the per-monitor spacing from calibration while re-anchoring the full pose map to the current motion frame.

## Targeting

Camera mode uses yaw and pitch.

AirPods mode uses yaw, pitch, and roll with normalized per-axis distances derived from the calibrated monitor spread. The current monitor still gets a hysteresis bonus to reduce flicker near boundaries.
