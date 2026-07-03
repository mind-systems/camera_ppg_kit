# Plan: Adaptive de-halving stage

## Context
Ship the note-29-chosen RR-domain harmonic-pair-merge de-halver as a pure, unit-tested `lib/src/processing/rr_dehalving.dart` stage placed **before** `RrAcceptance` in `CameraPpgSession._onSignal`, so the acceptance gate's rolling median only ever sees de-halved beats — killing the peak-halving inversion the two calibration runs exposed. Rate-proportional throughout; public streams unchanged.

## Settings
- Testing: yes (milestone explicitly requires fixture regression + unit tests)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Port the stage

- [x] **Task 1: Create the `RrDehalving` processing stage**
  Files: `lib/src/processing/rr_dehalving.dart`
  Port the core algorithm of `HarmonicMergeCandidate` from `test/dehalving/candidates/harmonic_merge.dart` into a production stage named `RrDehalving`. Keep it a **pure** `src/processing/` file — import **only** `../models/rr_interval.dart` (ARCHITECTURE dependency rule: no `camera`/`flutter_ppg`/channel imports).
  - Constructor params + defaults ported **as-is**: `bootstrapBeats = 3`, `shortFraction = 0.75`, `pairTolerance = 0.30`, `trackerAlpha = 0.1`, `fullBeatTolerance = 0.40`. Keep them constructor parameters (tunable), not hardcoded — note 34 will promote validated numbers.
  - Port the state machine verbatim: bootstrap (median-of-first-`bootstrapBeats` seeds `_trackedPeriodMs`), short/full classification (`rr.intervalMs < trackedPeriod * shortFraction`), pending-pair merge with `pairTolerance`, tracker EMA update (`trackerAlpha`) on merges and on full beats within `fullBeatTolerance`, plus the `_ema`/`_median` helpers and the internal `Queue<RrInterval>` output buffer.
  - Public surface, matching the pinned output contract in note 30 (2:1 pair-merge, **not** 1:1 like `RrAcceptance.evaluate`): `RrInterval? evaluate(RrInterval rr)`, `List<RrInterval> flush()`, `void reset()`.
  - **Drop the offline-scoring scaffolding**: `BeatOutcome`, the `_decisions`/`outcomes` list, its `assert`, and the `_pendingIndex` field. That machinery exists only to feed `test/dehalving/scoring.dart` and would grow unbounded over a live session — it is not a production concern. Keep the lightweight `double? get trackedPeriodMs` and `int? get convergedAtBeatIndex` getters (cheap diagnostics, note 30). Merged output must still carry the incoming `rr.timestamp` exactly as the reference does.
  - **Porting hazard — preserve the `convergedAtBeatIndex` source when stripping `_decisions`.** In the reference, the beat index that `convergedAtBeatIndex` records comes from `final index = _decisions.length;` (harmonic_merge.dart:99, 107). Removing `_decisions` deletes that source. Replace it with a standalone `int _beatIndex = 0;` incremented once at the top of `evaluate`, and set `_convergedAtBeatIndex = _beatIndex` at bootstrap convergence. `_handleShort`/`_handleFull` then no longer take an `index` param at all. `reset()` must also zero `_beatIndex`. Verify the getter still returns the convergence beat — Task 6 asserts it.
  - **No barrel export** — `lib/camera_ppg_kit.dart` is untouched; `RrDehalving` stays internal (note 30: unlike `RrAcceptance`/`SessionPolicy`, it gets no `[debug]` export).

### Phase 2: Wire into `CameraPpgSession`

- [x] **Task 2: Add the injectable `_dehalving` field** (depends on Task 1)
  Files: `lib/src/api/camera_ppg_session.dart`
  Import `../processing/rr_dehalving.dart`. Add constructor param `RrDehalving? dehalving` to `CameraPpgSession(...)` and a `final RrDehalving _dehalving;` field initialized `_dehalving = dehalving ?? RrDehalving()`, mirroring the existing `_policy`/`_acceptance` injection pattern (constructor ~line 50-58, fields ~line 66-77). The param type stays unexported — consumers omit it (it is optional/nullable), the same way `mind_mobile` omits `policy`/`acceptance`. Add a doc comment mirroring `_acceptance`'s, pointing at note 30.

- [x] **Task 3: Route trusted beats through de-halving before the gate** (depends on Task 2)
  Files: `lib/src/api/camera_ppg_session.dart`
  In `_onSignal`'s RR-gating block (~line 558-576), restructure the `for (final rr in newIntervals)` loop per note 30's wiring diagram (`candidate → RrDehalving.evaluate → RrAcceptance.evaluate → rrStream`). For each `rr`, build the raw `candidate` `RrInterval` as today, then:
  - Feed **every** trusted `candidate` to `_dehalving.evaluate(...)`, in order, unconditionally — the stage's pending/pair state depends on seeing every beat, so a dropped feed corrupts the next merge decision.
  - **Move the `if (_rrController.isClosed) continue;` guard off the feed and onto the emit.** The current loop tests `isClosed` at the top of the iteration (line 559), *before* the beat is consumed. That must not gate `_dehalving.evaluate(...)`. Only when the stage returns a **non-null** interval do we run it through `_acceptance.evaluate(...)` and `_rrController.add(...)` — and only that terminal `add` needs the `isClosed` guard. A teardown-race tick still feeds the stage but skips the closed-controller `add`.
  - Because the stage buffers, a single input may return `null` (beat held pending) — that is expected; do not force 1:1 parity with the old loop. The tracked period/median now only ever sees de-halved output.

- [x] **Task 4: Reset (and drain) the stage in the teardown lifecycle** (depends on Task 3)
  Files: `lib/src/api/camera_ppg_session.dart`
  In `_release()` (~line 418-441), call `_dehalving.reset()` at the same lifecycle point as the existing `_acceptance.reset()` (line 431), so a new measurement re-arms cold-start on both stages. **Do not call `flush()` here.** Note 30 permits discarding the tail beats when the session is stopping, and `reset()` already clears `_outQueue`/`_pending`/tracker/bootstrap unconditionally — so a `flush()` whose return is discarded immediately before `reset()` is a functional no-op that would only invite a future reader to "fix" it by piping the drained tail into a tearing-down `_rrController`. Just `reset()`. (If a later milestone wants to actually emit the tail, that is a deliberate change, not this task.) Keep the frame-isolate close-before-cancel teardown ordering (`_tearDownHandles`) untouched — `RrDehalving` never touches isolate/camera state, so this is pure ordering hygiene, not a new teardown surface.

### Phase 3: Regression + unit tests

- [x] **Task 5: Fixture regression tests (BPM within counting error)** (depends on Task 1)
  Files: `test/processing/rr_dehalving_test.dart`
  Replay **both** `.calibration` fixtures through a fresh production `RrDehalving` and assert the derived BPM lands within counting error of each file's reference. Reuse the existing harness rather than rewriting: import `../dehalving/fixture.dart` (`loadAll()`, `CalibrationFixture.toRrIntervals()`, `referenceBpm`) and `../dehalving/scoring.dart` (`classifyBeat`).
  - For each fixture: feed `fixture.toRrIntervals()` through `evaluate`, collect non-null outputs, then append `flush()`; compute `derivedBpm = (60000 / mean(acceptedMagnitudesMs)).round()`; assert BPM within counting error. **Tolerance = `<= 5`, not `<= 3`.** `dehalving_eval_test.dart` asserts `lessThanOrEqualTo(_countingErrorBpm + 2)` with `_countingErrorBpm = 3.0` — i.e. an effective `<= 5` (line 55). The `+2` margin exists because note 30's evidence table records harmonic-merge **fixture 2 error = +4.9** on exactly this pre-gate path (`evaluate` non-null + `flush()`, no downstream `RrAcceptance`). A `<= 3` bound would fail fixture 2 and make Commit 2 unreachable. Reuse the harness form `_countingErrorBpm + 2` (or a literal `5.0`) so the intent is legible. Fixture 1 (≈+0.8) clears it comfortably; fixture 2 (≈+4.9) is the binding case — optionally assert fixture 2's known ≈+4.9 explicitly rather than only the shared bound.
  - Secondary black-box check reusing `classifyBeat` on the **accepted** magnitudes: assert the true cluster is well-represented and the halved cluster is overwhelmingly absent (note 29's 98%+ halved-removal result). Keep the halved-cluster bound loose enough to tolerate the known small residual (do not assert exactly zero). These assertions validate the shipped `RrDehalving` output directly — no per-beat outcome instrumentation needed.

- [x] **Task 6: Focused unit tests for the stage mechanics** (depends on Task 1)
  Files: `test/processing/rr_dehalving_test.dart`
  Add targeted cases exercising the state machine directly with synthetic intervals (not fixtures): bootstrap converges after `bootstrapBeats` (median seeds `trackedPeriodMs`, `convergedAtBeatIndex` set); two consecutive short beats summing within `pairTolerance` merge into one interval carrying the second beat's timestamp; a short beat followed by a full beat is flushed standalone (failed pairing does **not** update the tracker); a full beat outside `fullBeatTolerance` does not move the tracker; `flush()` drains a still-pending beat standalone; `reset()` clears all state so a second run behaves identically to a fresh instance. Confirm `evaluate` returns `null` while a beat is held pending.

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add adaptive RR de-halving stage and wire it before the acceptance gate"
- **Commit 2** (after tasks 5-6): "Add de-halving fixture regression and unit tests"
