# Plan: Kit — open-ended measurement session (no auto-complete)

## Context
Removes the leftover "measure-for-60 s → done" semantic from the kit so a started session streams RR indefinitely (`idle → warmup → measuring ⇄ poorSignal`), ending only on Stop/dispose — matching the open-ended source model (note 22 / neiry parity). The only 60 s left is the calibration screen's countdown (note 21).

## Settings
- Testing: yes (existing unit tests reference the removed `targetDuration`/`done` symbols and must be updated to keep `flutter test` green — no new test surface is added)
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Kit core — remove the target-duration/done machine

- [x] **Task 1: Strip `targetDuration` and the `measuring → done` transition from `SessionPolicy`**
  Files: `lib/src/processing/session_policy.dart`
  Remove:
  - the `targetDuration` ctor param + field (lines ~25, ~38-39);
  - the `_measured` accumulator field (~55-56) and its removal from `reset()` (~79);
  - the whole per-tick delta/accumulator block at lines 105-109 (`final delta = elapsed - _lastElapsed;`, `final enteredMeasuring = …`, `if (enteredMeasuring) _measured += delta;`);
  - the `_lastElapsed` field + its doc (~58-59), its `_lastElapsed = Duration.zero;` line in `reset()` (~79), and the trailing `_lastElapsed = elapsed;` at the end of `onSignal` (~152) — once `delta` is gone, line 105 is `_lastElapsed`'s **only reader**, so keeping either write leaves an assigned-but-never-read field (`unused_field` analyzer warning). Delete `delta`, `_measured`, **and** `_lastElapsed` together;
  - the `if (_measured >= targetDuration) _state = MeasurementState.done;` branch in the `measuring` case (~124-135, keeping only the `!accepted`/`else` poorSignal logic);
  - the whole `case MeasurementState.done:` terminal arm (~146-149).

  After these removals `onSignal` holds no delta/last-elapsed/accumulator bookkeeping — it computes `accepted`, runs the entry-state `switch`, and returns `_state`. None of the surviving transitions reads `_lastElapsed` (`warmup → measuring` on absolute `elapsed >= warmupDuration`; `measuring → poorSignal` via `_badSince` + absolute `elapsed`; `poorSignal → measuring` on `accepted`), so nothing else depends on it.

  Doc updates: rewrite the class doc comment (lines 4-21) and the `measuring`/`poorSignal` field doc comments so they no longer describe "when are we done"/target-duration accounting, **and** rewrite the `onSignal` method-level "Per-tick ordering" doc block (lines ~83-96) to the reduced ordering — steps 1 (compute `delta`), 2 (accumulate measured time), and 4 (update the last-elapsed marker) describe deleted machinery; the block should read: evaluate acceptance → run the entry-state transition → return the new state. Keep the warm-up, silence-window, and poorSignal ⇄ measuring behavior exactly as-is. Result: states are `idle → warmup → measuring ⇄ poorSignal`, and the machine never self-terminates.

- [x] **Task 2: Drop `done` from the `MeasurementState` enum** (depends on Task 1)
  Files: `lib/src/models/measurement_state.dart`
  Remove the `done` enum value (lines 17-18) and its doc comment. Enum becomes `idle`, `warmup`, `measuring`, `poorSignal`.

- [x] **Task 3: Update kit unit tests for the removed symbols** (depends on Task 1, Task 2)
  Files: `test/session_policy_test.dart`, `test/models_test.dart`
  In `session_policy_test.dart` remove the two tests that assert the target-duration/`done` behavior: `'accumulated measuring time reaching targetDuration flips to done, and done is terminal'` (~170-214) and `'poorSignal time does not count toward targetDuration…'` (~216-298). Remove any remaining `targetDuration:` ctor args from other `SessionPolicy(...)` constructions in the file. Keep every warm-up / silence-window / poorSignal ⇄ measuring test. In `models_test.dart`, change the `'has exactly the five expected lifecycle values'` test to assert the four remaining values (drop `MeasurementState.done` at line 63) and rename the description to "four expected lifecycle values".

### Phase 2: Example — clean the now-dead `done` branches

- [x] **Task 4: Remove `targetDuration` from the session-config provider** (depends on Task 1)
  Files: `example/lib/providers/session_config_provider.dart`
  Delete the `setTargetSeconds` mutator (~52-62) and remove the `targetDuration:` argument from every `SessionPolicy(...)` reconstruction inside `setWarmupSeconds`, `setSilenceSeconds`, and `setSqiFloor` (lines 45, 69, 81). `SessionConfig.defaults()` already relies on the kit's own defaults, so no numbers change here.

- [x] **Task 5: Drop the `done` reset case from `bpmProvider`** (depends on Task 2)
  Files: `example/lib/providers/stream_providers.dart`
  In `BpmNotifier`'s `stateStream` listener (~57-67) remove the `case MeasurementState.done:` label (keep `idle`/`warmup` → `state = null` and `measuring`/`poorSignal` → break). Update the doc comment above `BpmNotifier` (~40-43) so it no longer mentions `done`. Also fix the `stateProvider` doc comment at line 19 — change "warm-up/measuring/poorSignal/done state machine" to drop `/done`, since that state no longer exists.

- [x] **Task 6: Clean the Source screen's `done` recovery path and banner** (depends on Task 2)
  Files: `example/lib/screens/source_screen.dart`
  In `_start` remove the `if (currentState == MeasurementState.done) { … service.stopMeasurement(); }` block and its comment (~104-111) — Start is simply disabled while running. After that removal `_start`'s `currentState` parameter is unused, so change the signature to `_start()` (no param) and update **both** call sites: `source_screen.dart:231` (`onPressed: isRunning ? null : () => _start()`, the Start button) and `source_screen.dart:213` (the retry banner → `_start()`). Also delete the now-stale retry-banner comment at lines 211-212 ("A failed start() always leaves the session at `idle` … retry never needs the `done`-recovery path"). Remove the `MeasurementState.done => ('Complete', …)` arm from the `_stateBanner` switch (~170). In `build`, simplify the `isRunning`/`canStop` comment block (~131-140) to drop the `done`-terminal reasoning (the three-state `isRunning` expression stays as-is). In the `[debug]` panel remove the `_intField('Target duration (s)', policy.targetDuration.inSeconds, notifier.setTargetSeconds)` line (~354).

- [x] **Task 7: Drop the `done` banner arm from the Kit-API and Calibration screens** (depends on Task 2)
  Files: `example/lib/screens/kit_api_tab.dart`, `example/lib/screens/calibration_screen.dart`
  Remove the `MeasurementState.done => ('Complete', Colors.indigo),` arm from the state switch in each file (`kit_api_tab.dart:80`, `calibration_screen.dart:237`) so both switches are exhaustive over the four-value enum. No other behavior changes.

- [x] **Task 8: Remove the dormant `done`-finalize path from the calibration recorder** (depends on Task 2)
  Files: `example/lib/calibration/calibration_recorder.dart`
  Remove the `_done` field (~31), the `isDone` getter + its doc (~33-35), the `_done = false;` reset in `start()` (~58), and the `_stateSub` state-stream listener whose sole job was setting `_done`/stopping the clock (~82-87) — along with the `_stateSub` field declaration (~39) and, in `stop()`, both its `_stateSub?.cancel()` and the `_stateSub = null;` at line ~99. (Keep the `dart:async` import — `_rrSub`/`_qualitySub` remain `StreamSubscription`.) Remove the `'targetMs': policy.targetDuration.inMilliseconds,` line from the exported run metadata (~144). `save()` is not gated on `isDone` — the calibration screen drives `stop()` (note 21) — so no save-flow logic changes. Note the exported JSON `schemaVersion` stays `1`: `policy.targetMs` simply disappears from the metadata under the same version — acceptable for this dev-only calibration artifact (note 20), but flagged so anyone whose analysis tooling keys on it is aware.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Remove target-duration self-completion from kit session policy"
- **Commit 2** (after tasks 4-8): "Clean dead done-state branches from example screens and recorder"
