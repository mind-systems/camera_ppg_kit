# Plan: State & error types

## Context
Add the kit's control/error surface — `MeasurementState`, `FingerPresence`, and a typed, never-thrown `CameraPpgError` — as pure-Dart value types crossed over the API boundary (never as exceptions), completing Phase 3's model layer alongside the existing data types (`RrInterval`, `SignalQuality`).

## Settings
- Testing: yes (milestone explicitly requires tests)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model types

- [x] **Task 1: Add `MeasurementState` enum**
  Files: `lib/src/models/measurement_state.dart`
  Add `enum MeasurementState { idle, warmup, measuring, done, poorSignal }` — the lifecycle the UI binds to and what the future `CameraPpgSession.stateStream` emits. Pure Dart, no native channel (the Phase-2 spike confirmed the kit needs no native code). Add a dartdoc comment per value describing the lifecycle meaning (idle = not started, warmup = acquiring before RR is trusted, measuring = emitting trusted intervals, done = target duration reached, poorSignal = quality/finger gate failing). Follow the doc-comment style of the existing `lib/src/models/signal_quality.dart`.

- [x] **Task 2: Add `FingerPresence` type + classification**
  Files: `lib/src/models/finger_presence.dart`
  Add `enum FingerPresence { present, absent, overBright }`. `overBright` means direct flash into the lens (finger not covering) and MUST be distinguishable from `absent` so the UI can guide "press your finger over both the lens and the flash", and so auto-detect's round-trip treats any not-covered reading (over-bright included) as "move to the next sensor".

  **Classify from the raw red-channel intensity, not a pre-collapsed bool.** `flutter_ppg`'s `PPGSignal` exposes `rawIntensity` (double); finger presence is *derived* from it by `SignalQualityAssessor.isFingerPresent(rawIntensity)` as a two-sided band (`rawIntensity > fingerPresenceMin && rawIntensity < fingerPresenceMax`) — so a single `bool` cannot separate too-dark (absent) from too-bright (overBright). The factory must therefore take the continuous value:
  - Signature: `FingerPresence.fromRawIntensity(double rawIntensity)` (the later API layer passes `signal.rawIntensity`).
  - Logic mirrors `flutter_ppg`'s band exactly: `rawIntensity <= _presenceMin → absent`; `rawIntensity >= _overBrightMax → overBright`; otherwise (`> _presenceMin && < _overBrightMax`) → `present`. Keep boundary handling consistent with `flutter_ppg` (which uses strict `>`/`<`, so exactly-min classifies as `absent` and exactly-max as `overBright`).
  - Declare **two** provisional `const` thresholds — a dark/absent floor `_presenceMin` and an over-bright ceiling `_overBrightMax` — mirroring `flutter_ppg`'s `PPGConfig.fingerPresenceMin` / `fingerPresenceMax` defaults (`30.0` / `250.0`), documented as provisional/tune-here-later the same way `signal_quality.dart` documents `_goodSnrThreshold`/`_fairSnrThreshold`.
  - NaN guard: NaN fails all comparisons (as in `SignalQuality.fromSnr`), so it would fall through to `present`; instead check `rawIntensity.isNaN` first and return `absent` (no valid reading = not present), documenting the choice.

- [x] **Task 3: Add typed `CameraPpgError`**
  Files: `lib/src/models/camera_ppg_error.dart`
  Add a typed, never-thrown error value modeled on `neiry_kit`'s `NeiryError` (class + code enum) for consistency: `enum CameraPpgErrorType { permissionDenied, cameraUnavailable, torchUnavailable, unsupportedDevice, noFinger, poorSignal }` and an `@immutable class CameraPpgError` carrying `final CameraPpgErrorType type; final bool permanentlyDenied; final String? message;`. `permanentlyDenied` is only meaningful for `permissionDenied` (default `false`). Provide named factory constructors for each type for ergonomic construction at the call site.

  For the cases that originate at the `camera` plugin edge (permission, torch/camera unavailable), provide a **code-string mapping** factory, not a `fromMap`. The kit has no native channel (Phase-2 spike), so there is no map to deserialize — the `camera` plugin surfaces failures as `CameraException(String code, String? description)` with codes like `CameraAccessDenied` / `CameraAccessDeniedWithoutPrompt`. So expose a pure `CameraPpgError.fromCameraErrorCode(String code, {String? description})` that maps: `CameraAccessDenied` → `permissionDenied`; `CameraAccessDeniedWithoutPrompt` (or restricted) → `permissionDenied` with `permanentlyDenied: true`; torch/unavailable codes → `torchUnavailable` / `cameraUnavailable`; unknown code → `cameraUnavailable` with the raw code carried in `message`. The later API layer calls this at the `CameraException` catch site. Do NOT add an `orNull`/numeric-sentinel path — this type carries no numeric field. Keep `unsupportedDevice` data-driven per its dartdoc (the deny-list lands in Phase 9) — do NOT hard-code model names here. Guard: this is a value; nothing in this file throws across a channel.

- [x] **Task 4: Export from the barrel**
  Files: `lib/camera_ppg_kit.dart`
  Add `export 'src/models/measurement_state.dart';`, `export 'src/models/finger_presence.dart';`, and `export 'src/models/camera_ppg_error.dart';` alongside the existing `rr_interval` / `signal_quality` exports. Consumers import only the barrel, never `src/` directly (per `.ai-factory/rules/base.md`).

### Phase 2: Tests

- [x] **Task 5: Unit tests for the three types** (depends on Tasks 1-4)
  Files: `test/models_test.dart`
  Extend the existing test file (do not create a new one) with three new `group`s, following the arrange/expect style already present:
  - `MeasurementState`: assert the enum has exactly the five expected values (guards against accidental additions/renames).
  - `FingerPresence.fromRawIntensity`: assert classification around **both** thresholds — below/at the dark floor → `absent`, at/above the over-bright ceiling → `overBright`, mid-band → `present` — with explicit boundary cases at exactly `_presenceMin` (→ `absent`) and exactly `_overBrightMax` (→ `overBright`), plus the NaN → `absent` behavior chosen in Task 2.
  - `CameraPpgError`: assert each named factory sets `type` and defaults `permanentlyDenied` to `false`; assert `permissionDenied` with the permanently-denied flag set; assert `fromCameraErrorCode` maps `CameraAccessDenied` → `permissionDenied`, `CameraAccessDeniedWithoutPrompt` → `permissionDenied` with `permanentlyDenied: true`, and an unknown code → `cameraUnavailable` carrying the raw code in `message`.
  Run `/usr/local/bin/flutter test` and confirm green.

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add measurement state, finger presence, and camera error types"
- **Commit 2** (after task 5): "Test state and error model types"
