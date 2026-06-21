# Session Policy — Warm-up / Duration / Acceptance

**Date:** 2026-06-21
**Source:** `flutter_ppg` 0.2.4 docs ("session control should live in your app"); DESCRIPTION.md NFRs; note 07

## Key Findings

- `flutter_ppg` explicitly leaves session control to the host: it streams `PPGSignal`s continuously but does not decide when a measurement has warmed up, when it is "good enough", or when it is done. The kit must own that policy so consumers get a clean "measure now → trusted result" interaction rather than a raw firehose.
- **This is core kit functionality, on by default with concrete defaults** — `warmupDuration = 5 s`, `targetDuration = 60 s`, `silenceWindow = 3 s`, SQI floor = `Poor` (all spike-tunable, Phase 2/8 may revise). `mind_mobile` must NOT reimplement the warm-up→done lifecycle — it gets a trusted measurement out of the box and only renders the `MeasurementState`. The example app (note 14) exists in part to *prove these defaults work with zero configuration* before the host depends on them; they are overridable but never required.
- Three concerns: a **warm-up** window (first ~3–5 s of RR are unreliable while the AGC/finger settle — suppress them), a target **duration** (30–60 s for stable HRV per the harness findings), and **acceptance** gating on `SignalQuality` + finger-presence (emit `poorSignal` + guidance instead of bad intervals).
- This drives `MeasurementState` transitions (idle → warmup → measuring → done / poorSignal) and is layered on the bare session (note 07) — independently shippable, one reason to revert.

## Details

### Added on `CameraPpgSession`

A policy object (constructor-injected, tunable). Because it is constructor-injected, the example app's settings playground (note 14) surfaces `warmupDuration` / `targetDuration` / SQI floor as **live knobs** a developer can twiddle and watch on the streams — the example does not dramatize the state machine as a guided UX. The policy controls:
- **Warm-up (after auto-detect locks the camera):** camera auto-detect (note 08) runs first, on Start, as a one-shot round-trip; once it locks a covered sensor, `stateStream` enters `warmup` for `warmupDuration` with RR withheld (or marked) while the AGC/finger settle and the pulse is confirmed — do not forward warm-up beats to `rrStream` as trusted. If the round-trip finds no covered sensor, the session surfaces a typed `CameraPpgError` and stays idle; it does not enter `warmup`.
- **Duration:** after `targetDuration` of `measuring`, transition to `done` and stop forwarding (the host can read accumulated intervals).
- **Acceptance:** when `SignalQuality` drops to `poor` or finger-presence is absent/over-bright for a `silenceWindow`, transition to `poorSignal` and surface guidance; resume `measuring` when quality recovers. Mirrors neiry's active-RR-source silence-window + artifact handling so the host policy is consistent across sources.

### State machine

`idle → warmup → measuring ⇄ poorSignal → done`. Emit every transition on `stateStream`. Keep thresholds (warm-up length, silence window, SQI floor) as named, spike-tunable constants.

### Verify

Unit-test the state machine with a fake `PPGSignal` sequence: warm-up suppresses early RR; a quality dip flips to `poorSignal` and back; elapsed `targetDuration` flips to `done`. No camera needed for the policy test (inject a synthetic signal stream).

### Guards

- Policy must be testable without hardware — keep it a pure function of (signal events, elapsed time), not coupled to `CameraController`.
- Do not discard artifact intervals here — the acceptance gate (Phase 8) marks `isArtifact`; this layer decides *session state*, not per-beat validity. Keep the two concerns separate.
