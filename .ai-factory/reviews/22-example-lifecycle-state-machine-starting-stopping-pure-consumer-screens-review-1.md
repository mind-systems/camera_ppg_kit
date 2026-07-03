# Code Review: Example lifecycle state machine (starting/stopping) + pure-consumer screens

**Reviewed:** working-tree diff vs `HEAD` (staged + unstaged).
**Scope:** `example/lib/services/source_lifecycle.dart` (new), `example/lib/services/camera_ppg_service.dart`, `example/lib/providers/stream_providers.dart`, `example/lib/screens/source_screen.dart`, `example/lib/screens/streams_screen.dart`, `example/lib/screens/calibration_screen.dart`, `example/lib/main.dart`. (Roadmap/note doc edits also present; not code, not reviewed for correctness.)

## Verdict

No correctness, security, or runtime-breaking defects found. The implementation matches the plan and note 33 faithfully. Every scope guard holds (kit `lib/` untouched, no `done` state, note-32 idle push preserved and absorbed, kit teardown order unchanged).

## What was verified against the actual code (not just the diff)

**Fold logic is driven only by real transitions, not frame cadence.** `CameraPpgSession._setState` (`lib/src/api/camera_ppg_session.dart:596-602`) short-circuits on `_state == next`, so `stateStream` emits only on genuine state changes. Therefore the new `_foldLifecycle` → `_setLifecycle` path — and its `ppgLog('lifecycle: … -> …')` — fires only on actual `warmup/measuring/poorSignal` transitions, never on every processed frame. The "minimal logging" intent holds; no log spam at ~24–30 FPS. `_setLifecycle` is also never invoked with `prev == next` at any live call site, so there are no redundant self-transition emits/logs either.

**`starting → warmup` fold captures the first emit.** On a successful `start()`, the kit emits `MeasurementState.warmup` (`camera_ppg_session.dart:345`) *before* `start()` returns, and the bridge subscription is wired (`camera_ppg_service.dart:137-145`) before `await session.start()` (line 149). Lifecycle stays `starting` until that warmup is delivered, and the fold guard permits folding while `starting`, so `starting → warmup` always lands.

**The fold guard cannot swallow a legitimate idle.** The kit only reaches `MeasurementState.idle` via `_release()` (`camera_ppg_session.dart:439`), which is called exclusively from `stop()`, `dispose()`, and `start()`'s failure/teardown paths — never autonomously mid-measurement. In every such case the service has already set lifecycle to `stopping` (via `stopMeasurement`) or `starting` (failed start), so ignoring the folded kit `idle` is correct: the authoritative `idle` comes only from the `stopMeasurement` teardown path. No path leaves lifecycle stuck showing `measuring` after the kit has actually gone idle.

**Failed-start path settles to idle.** `starting` → `start()` returns error → `await stopMeasurement()` (session still non-null) → `stopping` → teardown → `idle`. The interim kit `idle` emitted by `_release()` during the failed start is folded while lifecycle is `starting` and correctly ignored (switch `idle → break`), so there is no spurious `starting → idle` flicker.

**Start/Stop concurrency (Raw-entry stop during `starting`) does not desync.** If `stopMeasurement()` runs while `startMeasurement` is suspended on `await session.start()`: it sets `stopping`, cancels/clears `_subs`, nulls `_session`, tears down, then sets `idle`. When `start()` resumes, it either returns `null` (stale/abandoned — `camera_ppg_session.dart:334`), leaving lifecycle at `idle`, or returns an error and re-enters `stopMeasurement` whose no-session branch is a guarded no-op (lifecycle already `idle`). Terminal state is `idle` either way.

**Teardown-during-stop late emits are guarded.** `stopping` is set synchronously at `stopMeasurement` entry, before the `await sub.cancel()` loop, so any kit emit arriving between entry and cancellation hits the `_lifecycle == stopping → return` guard and cannot bounce lifecycle off `stopping`. The note-32 `_stateController.add(MeasurementState.idle)` push is preserved and `_setLifecycle(idle)` added alongside, exactly as specified.

**No-session early-return branch** does not emit a spurious `stopping` and defensively settles a stray non-idle lifecycle — matches the plan.

**Switch exhaustiveness / compile.** `MeasurementState` is a 4-value enum (`idle/warmup/measuring/poorSignal`; `done` removed by note 23), so `_foldLifecycle`'s switch is exhaustive without a default. All three screens' `_stateLabelColor` switches now cover the full 6-value `SourceLifecycle`. `pendingColor` (used for the new `starting`/`stopping` arms) exists in the widget kit. `SourceLifecycle.isActive`/`isTransitional` are used consistently.

**`calibration_screen.dart` import removal is safe.** The removed `package:camera_ppg_kit/camera_ppg_kit.dart` import previously supplied only `MeasurementState`, now replaced by `SourceLifecycle`. A grep confirms the file names no other kit type — `RrAcceptance`/`SessionPolicy` values flow through inferred types (`config.acceptance`/`config.policy` into `_recorder.start`) without being named, and the lone `[CameraPpgService]` reference is a dartdoc link (doc-tool concern, not a compile dependency). `streams_screen.dart` correctly keeps its kit import because it names `RrInterval` explicitly.

**Late-subscriber reasoning holds.** The shell keeps every screen mounted in one `IndexedStack` (`main.dart`), so `lifecycleProvider` is subscribed for the app's lifetime and receives every transition; the broadcast controller replays nothing, and screens default `?? SourceLifecycle.idle`, which is the correct pre-first-emit value. `lifecycleStream` is never fed an error, so `lifecycleProvider` never enters the error state.

## Minor, non-blocking observations (no action required)

- **`stateProvider` is now unused by `source_screen.dart`** after the banner/gating moved to `lifecycleProvider`. It remains correctly used by `streams_screen.dart` (RR-history clear on `warmup`) and `bpmProvider`, and `stream_providers.dart` is a whole-file import, so there is no unused-import/variable error — purely cosmetic.
- **Both control buttons render a spinner simultaneously during `starting`/`stopping`.** This matches the plan ("both buttons disabled + spinner"); noting only that two concurrent spinners is a deliberate visual, not a defect.
- **A slow/hanging `session.dispose()`** (the documented `camera_android_camerax` teardown hang) leaves lifecycle at `stopping` with the spinner until it returns. This is the intended "honest Stopping… progress" behaviour from note 33's Verify section, not a stuck state.

REVIEW_PASS
