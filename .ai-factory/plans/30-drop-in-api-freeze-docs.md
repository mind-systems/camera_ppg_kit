# Plan: Drop-in API freeze + docs

## Context
Freeze `lib/camera_ppg_kit.dart` so `mind_mobile` can add a `camera_ppg`-tagged RR-interval source with zero churn: audit the exported surface against spec note 19, explicitly label the `[debug]` extras, and ship consumer README/docs. No new behaviour — the audit and doc are the work.

## Settings
- Testing: no
- Logging: minimal
- Docs: yes

## Tasks

### Phase 1: Audit & freeze the barrel surface

- [x] **Task 1: Verify no wrapped/native types leak across the public boundary**
  Files: `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`
  Run the three note-19 "Verify" checks and confirm they pass; if any fails, wrap the leaking type in a `src/models/` value before proceeding.
  - `grep -rE 'flutter_ppg|CameraImage|CameraController|MethodChannel|PPGSignal' lib/camera_ppg_kit.dart` → no hits.
  - Every `export` in the barrel resolves to a `src/models/` or `src/api/` file (the two `src/processing/` re-exports in Task 2 are the only deliberate exception); `src/channel`, `src/util` are never exported.
  - Inspect every public member of `CameraPpgSession` (`rrStream`, `qualityStream`, `stateStream`, `fingerPresenceStream`, `resolvedCamera`/`resolvedCameraStream`, `buildPreview()`, `useCamera()`, `availableCameras()`, `start()`, `stop()`, `dispose()`, `debugSignalStream`) and confirm no `camera`/`flutter_ppg`/channel type appears in any signature — `buildPreview()` must return a plain `package:flutter` `Widget?`.

- [x] **Task 2: Reconcile and explicitly label the `[debug]` extras in the barrel; correct the stale `done` dartdoc** (depends on Task 1)
  Files: `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`
  The barrel diverged from note 19 in three ways the reconciliation must span (not only the note-30 one) — do **not** restore the barrel to note 19's literal text:
    (a) note 19 predates the note-30 `RrDehalving` stage (now a third ctor param);
    (b) note 19 names the debug **input** type as `RrAcceptanceConfig? acceptance`, but the real ctor param is `RrAcceptance? acceptance` (type renamed);
    (c) note 19 never mentions `SessionPolicy`/`policy` as an exported extra, yet the barrel exports it — ratified by ARCHITECTURE.md line 41.
  - Keep the two existing `[debug]` re-exports (`RrAcceptance`, `SessionPolicy`) and confirm `RrDehalving` stays **unexported** — its type not crossing the barrel means the host cannot construct it, so it is internal-default-only, not a public knob.
  - Rewrite the barrel's `[debug]` comment block to enumerate the debug surface exactly against current code: the optional `policy`/`acceptance` ctor inputs (present for the example's live-tuning playground, always omitted by `mind_mobile`) and the `Stream<List<double>> debugSignalStream` output (red-channel waveform for the example's signal-existence diagnostic). State plainly that neither is part of the drop-in contract.
  - Add a one-line comment marking the frozen consumer surface (the `CameraPpgSession` streams/state machine, camera-coverage UX methods, and the exported model types) as the supported drop-in contract, so a future edit knows adding to it is a deliberate post-freeze act.
  - **Fix the stale state-machine dartdoc** on `CameraPpgSession._state` (`camera_ppg_session.dart:103`): it currently reads `warmup → measuring ⇄ poorSignal → done`, but there is no `done` state — `MeasurementState` defines only `idle, warmup, measuring, poorSignal`. Correct it to `idle → warmup → measuring ⇄ poorSignal`, returning to `idle` on `stop()`. A frozen surface whose dartdoc names a nonexistent state is not honest; the code and the new README (Task 4) must agree.

### Phase 2: Consumer documentation

- [x] **Task 3: Update the README Status section to a stable-surface statement** (depends on Task 2)
  Files: `README.md`
  Replace the "Early stage / being built out" Status text with a stable-surface statement: the Dart API exported from `package:camera_ppg_kit/camera_ppg_kit.dart` is frozen as the drop-in RR-interval source surface; additions are a deliberate post-freeze act. Describe behaviour, not code — no directory tree, no API method table.

- [x] **Task 4: Add a "Consuming as a heart-rate source" section to the README** (depends on Task 3)
  Files: `README.md`
  Add a short section covering, in prose: import the barrel only; subscribe to the three streams (RR intervals, signal quality, measurement state) and the `idle → warmup → measuring ⇄ poorSignal` state machine (returning to `idle` on `stop()`; there is **no** `done` terminal state — `MeasurementState` is `idle, warmup, measuring, poorSignal` only); the source emits **RR only** (no HR/BPM/HRV stream — the consumer derives those from the intervals); on lost finger/poor signal the RR stream simply goes silent (no zero/placeholder ticks, no exception) so the host's silence-window fallback fires; `RrInterval.isArtifact` is the single artifact channel. State explicitly that the `camera_ppg` `SensorSource` tag and the `lib/Biometrics/` adapter registering this kit into `ActiveRrSource` belong in **mind_mobile**, not here. Name the `[debug]` extras (Task 2) as unsupported so no consumer mistakes them for the contract. No directory tree, no method table.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Freeze camera_ppg_kit public barrel and label debug extras"
- **Commit 2** (after tasks 3-4): "Document camera_ppg_kit drop-in heart-rate source surface"
