# Kit — Open-Ended Measurement Session (no auto-complete)

**Date:** 2026-07-03
**Source:** on-device bug report ("Start → Measuring → Complete, everything stops"); note 09 (`SessionPolicy` — the behavior being **superseded, not rewritten**); note 22 (open-ended source model); neiry parity (a device connection never "completes")

## Key Findings

- **Bug:** pressing Start runs `warmup → measuring`, then after `SessionPolicy.targetDuration` (**60 s of accumulated measuring time**) the policy flips to the terminal `MeasurementState.done`. `rrTrusted` is true only in `measuring`, so at `done` the kit **stops emitting RR** — the UI shows "Complete" and the source is dead until Stop+Start. Start means "begin HR detection"; it must never self-complete.
- Root cause is in the **kit**, not the screens: `lib/src/processing/session_policy.dart:25` (`targetDuration = 60s`), `:125–126` (`measuring → done`), `:146` (`done` terminal). A leftover "measure-now-for-60 s" semantic that contradicts the open-ended source (note 22): the source streams RR as long as the finger is on, until the **host calls `stop()`** — exactly like neiry's device connection.
- The 60 s belongs **only** to the calibration recording window (screen-side countdown, note 21), never to the kit session.
- **This is a new forward task** — note 09 is left intact as the historical record of the policy as first built; the fix is not a rewrite of it.

## Details

### Current state (to change)

- `session_policy.dart` — `targetDuration` ctor param + field; the `measuring` case's `if (_measured >= targetDuration) _state = MeasurementState.done;`; the `_measured` accumulator; the `done` terminal case; the poorSignal-doesn't-count-toward-target accounting (all of it exists only to drive the target → done transition).
- `models/measurement_state.dart` — the `done` enum value.
- Consumers of `MeasurementState.done` (to clean): `example/lib/screens/source_screen.dart` (`_start` done-recovery branch, `_stateBanner` "Complete" arm, `isRunning`/`canStop` comments), `example/lib/screens/kit_api_tab.dart` ("Complete" arm), `example/lib/providers/stream_providers.dart` (`bpmProvider` resets on `done`), `example/lib/calibration/calibration_recorder.dart` (note 20 — the `_done`/`isDone` + `stateStream`-`done` listener, already documented "dormant").

### Target — open-ended session

- Remove `targetDuration` (ctor param + field), the `measuring → done` transition, and the now-unused `_measured` accumulation from `SessionPolicy`. States become `idle → warmup → measuring ⇄ poorSignal`; only `stop()`/`dispose()` returns to `idle`. The session **never self-terminates**.
- Remove `MeasurementState.done` from the enum and clean every dead branch above:
  - `source_screen.dart` — drop the `done`-recovery path in `_start` (Start is simply disabled while running); drop the "Complete" banner arm.
  - `kit_api_tab.dart` — drop the "Complete" banner arm.
  - `stream_providers.dart` `bpmProvider` — drop the `done` reset case (keep `idle`/`warmup`).
  - `calibration_recorder.dart` — remove the `_done`/`isDone` field + the `stateStream` `done` listener; `save()` never gated on it (the calibration screen drives `stop()`, note 21).
- Warm-up **stays** (RR untrusted during AGC settle) — only the target-duration/`done` removal is in scope.

## Guards

- Do not reintroduce any duration-based completion in the kit. The **only** 60 s is the calibration screen's countdown (note 21, screen-side).
- Public-surface change (the `MeasurementState` enum loses `done`) — record it for the note-19 freeze. Safe now: `mind_mobile` does not yet consume the kit (integration is Phase 10).
- Do not rewrite note 09 or note 20 (their specs stand); this task only changes code.

## Verify

- Start → `warmup` → `measuring`; keep the finger on for **>60 s** → stays `measuring`, RR keeps flowing, no "Complete", nothing stops.
- Stop → `idle`; Start again → works (no wedged terminal state).
- `grep -rn 'MeasurementState.done\|targetDuration' lib example/lib` → no hits.
