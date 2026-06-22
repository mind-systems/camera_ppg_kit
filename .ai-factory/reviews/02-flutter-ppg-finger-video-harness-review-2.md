# Code Review (round 2): flutter_ppg finger-video harness

**Plan:** `.ai-factory/plans/02-flutter-ppg-finger-video-harness.md`
**Scope reviewed:** `git diff HEAD` — 4 new code files + 2 modified, all under `example/lib/`.
**Build check:** `flutter analyze lib/` → **No issues found** (1.7s).
**Prior review:** `02-flutter-ppg-finger-video-harness-review-1.md` (3 non-blocking findings).
**Risk level:** 🟢 Low.

## Changes since review 1

The diff grew by the exact files flagged in round 1 (`fps_meter.dart` 39→44, `measurement_runner.dart` 189→194); the other four files are byte-identical to round 1. All three round-1 findings are now resolved:

1. **`FpsMeter.fps` no longer freezes on frame stall (review-1 finding 1) — FIXED.**
   `fps_meter.dart:33-43`: the getter now prunes against `DateTime.now()` before computing, so when frames stop arriving the reading decays to `0.0` instead of holding the last non-zero value. (Minor note: the getter now mutates `_timestamps` — a side-effecting getter — but it is harmless: Dart is single-threaded, so `record` (stream listener) and `fps` (UI timer) never interleave, and `record` already bounds the list independently. No correctness or growth issue.)

2. **`signals` getter doc comment corrected (review-1 finding 2) — FIXED.**
   `measurement_runner.dart:34-38`: the comment now states "Subscribe after `start` returns … the getter returns `Stream.empty`, which closes immediately with no data," matching the code.

3. **`start()` re-entrancy guard added (review-1 finding 3) — FIXED.**
   `measurement_runner.dart:57`: `if (_signalsCtrl != null) return;` prevents a second `start` from orphaning the first session's controller. Behavior is consistent: `_signalsCtrl` is created on entry and only nulled by `stop()`, so the guard holds for the whole session lifetime (including after a caught camera-open failure, where the runner stays idle until `stop()` — acceptable, and the sole caller starts exactly once in `initState`).

## Re-verified this round

- **Analyzer clean** on the full `lib/` after the edits.
- **Teardown** (`stop`) still captures-and-nulls all fields up front (idempotent), tears down in the correct order, and turns the torch off before disposing the controller. Handles the failed-start state (non-null `_signalsCtrl`, null controller/sub) without error.
- **Lifecycle** in `StreamInspectorScreen.dispose` (unchanged): cancels `_uiTimer`, cancels the UI `_sub`, then `stop()`s the runner; the periodic tick is `mounted`-guarded — no setState-after-dispose, no late stream callbacks.
- **Empty-`rrIntervals` guard** (unchanged): `—` for RR and BPM; divides only on a strictly-positive last interval.
- **`coverage_detector.dart` refactor** (unchanged): behavior-identical, `cfg` still consumed by `FlutterPPGService(config: cfg)`.
- **Plan constraints** all honored: example-only (nothing under `lib/src/`), raw passthrough, throttled ~3 Hz rebuilds, real-device-tolerant.

No new issues were introduced by the round-1 fixes, and no previously-missed defects surfaced on this independent pass.

REVIEW_PASS
