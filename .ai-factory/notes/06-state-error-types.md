# State & Error Types

**Date:** 2026-06-21
**Source:** conversation context; `neiry_kit` error-model conventions; `docs/core/error-handling.md` (mind_mobile pipeline)

## Key Findings

- The kit must report expected, recoverable conditions — permission denied, no finger, poor signal, unsupported device — as **typed values crossed over the boundary**, never as exceptions thrown across the platform channel (a core kit rule and ARCHITECTURE anti-pattern). This is the control/error half, independently shippable from the data path (note 05).
- `MeasurementState` is the lifecycle the UI binds to; `FingerPresence` and `CameraPpgError` are the diagnostic surface the session and the host map to user guidance.
- Reusing neiry's `orNull` sentinel keeps map deserialization consistent across kits.

## Details

### `lib/src/models/measurement_state.dart`

`enum MeasurementState { idle, warmup, measuring, done, poorSignal }` (mirror the channel enum, note 04). This is what `CameraPpgSession.stateStream` emits and what `MeasurementState`-driven UI watches.

### `lib/src/models/finger_presence.dart`

A small value type wrapping `flutter_ppg`'s finger-presence + light-intensity signal (present / absent / over-bright meaning direct-flash-into-lens, i.e. finger not covering). The over-bright case is the no-coverage failure mode and must be distinguishable so the UI can say "press your finger over both the lens and the flash" — and during auto-detect's round-trip (note 01) any not-covered reading, over-bright included, simply moves on to the next sensor.

### `lib/src/models/camera_ppg_error.dart`

A sealed/typed set of states, not thrown:
- `permissionDenied` (+ permanently-denied flag)
- `cameraUnavailable` / `torchUnavailable`
- `unsupportedDevice` (from the Phase 2 deny-list)
- `noFinger` / `poorSignal`

Carried out via `stateStream`/a dedicated error stream as values. Provide a `fromMap`/code mapping for the few that originate natively (permission, torch), using `orNull` for any nullable numeric.

### Export + tests

Export all three from the barrel. `test/models_test.dart`: enum code round-trips; `CameraPpgError` map deserialization for the native-originating cases; finger-presence classification thresholds.

### Guards

- No `throw` across the channel for any of these — they are values.
- Keep `unsupportedDevice` data-driven (deny-list), not hard-coded model names in this file.
