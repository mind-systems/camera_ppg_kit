# Plan: Warm-up / duration / acceptance gating

## Context
Add the session policy layer on top of the bare `CameraPpgSession`: a warm-up window that withholds early RR, a target measurement duration, and SQI + finger-presence acceptance gating — all driving `MeasurementState` (idle → warmup → measuring ⇄ poorSignal → done) so the host renders state instead of reimplementing the lifecycle.

## Settings
- Testing: yes (spec note 09 "Verify" explicitly mandates unit-testing the state machine against a synthetic signal stream)
- Logging: minimal (route state transitions through `nlog`)
- Docs: no

## Reference material (read before implementing)
- Spec: `.ai-factory/notes/09-session-policy.md` — the authoritative behavior.
- `lib/src/api/camera_ppg_session.dart` — the session to wire the policy into. Note `_onSignal` (line ~426) already converts `PPGSignal` → kit models and fans out streams; `start()` currently sets state to `measuring` directly (line ~281); `_release()` resets to `idle`.
- `lib/src/models/measurement_state.dart`, `finger_presence.dart` (`FingerPresence.fromRawIntensity`), `signal_quality.dart` (`SignalQuality.fromSnr`; enum order is `good`(0), `fair`(1), `poor`(2)).
- Prior art for tunable-constants + `reset()` pattern: `neiry_kit/lib/src/processing/ppg_peak_detector.dart`.
- Architecture rule: `src/processing/` must be **pure Dart** — no `camera`/`flutter_ppg`/Flutter imports — so it stays isolate-safe and hardware-free testable.

## Tasks

### Phase 1: Pure policy (processing layer)

- [x] **Task 1: Add the pure `SessionPolicy` state machine**
  Files: `lib/src/processing/session_policy.dart`
  Create a pure-Dart `SessionPolicy` class (no `camera`/`flutter_ppg`/Flutter imports — depends only on `../models/measurement_state.dart`, `signal_quality.dart`, `finger_presence.dart`). It is a pure function of (signal events, elapsed time) per the spec's Guard — it must **not** own a `Timer` or read a wall clock; the caller passes elapsed time in.
  - Constructor-injectable, spike-tunable fields with concrete defaults declared as named `lowerCamelCase` consts (Dart convention, not SCREAMING_CASE):
    - `warmupDuration = Duration(seconds: 5)`
    - `targetDuration = Duration(seconds: 60)`
    - `silenceWindow = Duration(seconds: 3)`
    - `sqiFloor = SignalQuality.poor` — the quality band at/below which the signal is rejected.
  - `MeasurementState get state` and a `bool get rrTrusted => state == MeasurementState.measuring` (host/session forwards RR only when trusted).
  - `void reset()` — call on each session start: sets state to `warmup`, clears the accumulated-measuring clock, clears the "bad-signal since" marker and the last-tick marker. (Analogous to `PpgPeakDetector.reset()`.)
  - `MeasurementState onSignal({required Duration elapsed, required SignalQuality quality, required FingerPresence presence})` — advances the machine and returns the new state. `elapsed` is monotonic time since `reset()`. Logic:
    - Acceptance predicate: `accepted = presence == FingerPresence.present && quality.index < sqiFloor.index`. With `sqiFloor = poor`, this rejects only `poor` (accepts `good`/`fair`); a lower floor (e.g. `fair`) would also reject `fair`. Finger `absent`/`overBright` always rejects.
    - **Per-tick ordering (deterministic — the Task 2 tests depend on this exact sequence):** (a) `final delta = elapsed - lastElapsed;` (b) add `delta` to a `_measured` accumulator **only if the state at tick entry was `measuring`** — i.e. accumulate *before* evaluating this tick's transitions, so the `warmup → measuring` and `poorSignal → measuring` transition ticks do **not** retroactively count the warm-up/silence gap as measuring time; (c) evaluate the transitions below; (d) **always** update `lastElapsed = elapsed` at the end, in every state, so `lastElapsed` never lags (this keeps the resume delta small).
    - **warmup:** stay in `warmup` until `elapsed >= warmupDuration`, then transition to `measuring`. Warm-up is a pure time-based suppression window — do not require acceptable signal to leave it (acceptance governs `measuring` afterwards).
    - **measuring:** when `_measured >= targetDuration` → `done`. Otherwise, if `!accepted`, start/continue a "bad since" marker; when bad continuously for `>= silenceWindow` → `poorSignal`. A single accepted tick clears the "bad since" marker.
    - **poorSignal:** when a tick is `accepted`, resume `measuring` immediately (spec: "resume measuring when quality recovers"); clear the "bad since" marker. `poorSignal` time does **not** count toward `targetDuration` (only time spent in `measuring` accumulates via step (b) above — this is the "of measuring" reading of the spec; document the choice inline).
    - **done:** terminal — remain `done` regardless of subsequent ticks until `reset()`.
  - Do **not** touch per-beat validity here — this layer decides session state only; `RrInterval.isArtifact` is the Phase-6 acceptance gate's concern (spec Guard). Keep the two separate.
  - Do not export from the barrel (`processing/` is internal per ARCHITECTURE.md dependency rules).

- [x] **Task 2: Unit-test the state machine** (depends on Task 1)
  Files: `test/session_policy_test.dart`
  Drive `SessionPolicy` with a synthetic sequence of `(elapsed, quality, presence)` ticks — no camera, no real clock — mirroring the existing pure-unit style in `test/camera_ppg_session_rr_conversion_test.dart`. Cover:
  - After `reset()`, state is `warmup` and `rrTrusted` is false.
  - Ticks before `warmupDuration` stay `warmup` (RR withheld); a tick at/after `warmupDuration` flips to `measuring` and `rrTrusted` becomes true.
  - While `measuring`, a run of unaccepted ticks (`poor` quality, or `absent`/`overBright` presence) shorter than `silenceWindow` stays `measuring`; sustained past `silenceWindow` flips to `poorSignal`; a later accepted tick resumes `measuring`.
  - Accumulated `measuring` time reaching `targetDuration` flips to `done`, and `done` is terminal (later accepted ticks do not revert it).
  - `poorSignal` time does not count toward `targetDuration` (a gap of bad ticks between measuring runs delays `done`). Use a **sparse** tick sequence (a `warmup → measuring` tick that jumps `elapsed` well past `warmupDuration`, and a `poorSignal → measuring` resume tick after a long gap) to assert the transition tick does **not** retroactively count the gap as measuring time — this exercises the per-tick ordering pinned in Task 1.
  - `sqiFloor` override (e.g. `fair`) additionally rejects `fair`-quality ticks.

### Phase 2: Wire the policy into the session + guidance

- [x] **Task 3: Drive `CameraPpgSession` state from the policy and gate RR forwarding** (depends on Task 1)
  Files: `lib/src/api/camera_ppg_session.dart`
  - Constructor-inject a `SessionPolicy` with a default instance (`this._policy = policy ?? SessionPolicy()`), so the example's settings playground can pass a tuned policy. Add the `import '../processing/session_policy.dart';`.
  - Add a `final Stopwatch _stopwatch = Stopwatch();` instance field as the monotonic time source for elapsed measurement time (production clock). The policy stays pure — only the session reads this clock and passes `_stopwatch.elapsed` in.
  - On successful lock (currently line ~281, `_setState(MeasurementState.measuring)`): call `_policy.reset()`, then `_stopwatch..reset()..start()` (a bare `.start()` after a prior cycle *resumes* accumulated time — the `reset()` is essential across repeated start/stop cycles; `Stopwatch` has no `restart()`), and set state to `MeasurementState.warmup` instead of `measuring`. In `_release()`, call `_stopwatch.stop()`.
  - In `_onSignal`: after computing `SignalQuality` (already done) and `FingerPresence.fromRawIntensity(signal.rawIntensity)`, call `final next = _policy.onSignal(elapsed: _stopwatch.elapsed, quality: quality, presence: presence);` then `_setState(next);`. Remove the unconditional `_setState(MeasurementState.measuring)` currently at the end of `_onSignal` (line ~460).
  - **RR gating — gate only the emit, not the bookkeeping:** the `diffNewIntervals(...)` call and the `_lastRrIntervals = signal.rrIntervals` update (currently lines 431–432) must run **every tick regardless of trust**. Only the `_rrController.add(...)` inside the `for` loop is guarded by `_policy.rrTrusted`. If the whole block were wrapped in `if (rrTrusted)`, `_lastRrIntervals` would stay stale through warm-up, and the first `measuring` tick would `diffNewIntervals(const [], currentWindow)` and dump the entire warm-up window as "trusted" — exactly the beats the spec says to withhold (same hazard on `poorSignal → measuring` resume). Keeping the diff/`_lastRrIntervals` update unconditional means warm-up/poorSignal beats are consumed and discarded, not deferred.
  - Update the `start()` dartdoc (~lines 136–139) — it currently states *"Returns `null` on success (state moves to `MeasurementState.measuring`)."* Success now moves to `warmup`; fix that sentence too.
  - During `warmup`/`poorSignal`/`done`, no RR reaches `rrStream`. Keep `qualityStream` and `debugSignalStream` flowing in all states (the host renders quality continuously).
  - Once `done`, keep the camera running but stop forwarding RR (state stays `done` until the host calls `stop()`); do not auto-release on `done` (that would reset state to `idle`).
  - Update the now-stale doc comments that describe warmup/done/poorSignal as "a later phase" to describe the real state machine: the `_state` field comment (~line 57) **and** the `start()` dartdoc success line (~lines 136–139) noted above.

- [x] **Task 4: Expose `fingerPresenceStream` for host guidance** (depends on Task 3)
  Files: `lib/src/api/camera_ppg_session.dart`
  The host needs to distinguish "press your finger" (`absent`) from "finger not covering the lens" (`overBright`) from "hold still / low SNR" to render the guidance the spec calls for; `qualityStream` alone cannot express this, and DESCRIPTION.md lists finger presence among the inspector's streams.
  - Add a `StreamController<FingerPresence>.broadcast()` opened in the constructor alongside the others, exposed as `Stream<FingerPresence> get fingerPresenceStream`, and closed in `dispose()` with the rest.
  - In `_onSignal`, emit the computed `FingerPresence` on it (guarded by `isClosed`), in every state.
  - No barrel change needed — the session file is already exported and `finger_presence.dart` is already in the barrel.

## Notes for the implementer
- Keep transition logging minimal: a single `nlog('state: <prev> → <next>')` at the point of change is enough; do not log every tick.
- Do not add a `Timer`-based `done`/`poorSignal` fallback — evaluation is tick-driven off the ~24 FPS frame stream, which is fine-grained enough and keeps the policy pure/testable. (If frames stop entirely, that is a camera failure handled by teardown, not this layer.)
- Adding `fingerPresenceStream` is a public-surface addition; note it for the Phase-10 API freeze (note 19) but implement it here for guidance.
