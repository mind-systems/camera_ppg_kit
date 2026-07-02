# Code Review (round 2): Calibration RR-capture + Android file export

**Reviewed:** `git diff HEAD` / `git status`
**Changed code files:**
- `example/lib/calibration/calibration_recorder.dart` (new, updated since round 1)
- `example/pubspec.yaml` / `example/pubspec.lock` (adds `path_provider`)

## Summary

Re-review after the round-1 fixes. Both actionable findings from review-1 are resolved, and the rest of the implementation continues to match the plan and spec note 20. No critical, blocking, or new correctness issues found.

## Round-1 findings — status

1. **Double-`start()` subscription leak — FIXED.** `start()` now calls `stop()` as its first statement (`calibration_recorder.dart:54`), cancelling and nulling any prior `_rrSub`/`_qualitySub`/`_stateSub` before re-subscribing. A re-entrant/double-tapped Start no longer orphans the previous three subscriptions. The comment at lines 51-53 documents the intent.

2. **`save()`-during-recording summary/intervals desync — FIXED.** `save()` snapshots the buffer with `final records = List<Map<String, Object?>>.of(_records)` (line 120) *before* the `await getExternalStorageDirectory()`, and every downstream read — `accepted`, `artifactCount`, `meanAcceptedRrMs`, `summary.totalIntervals`, and `'intervals': records` — uses that snapshot. A late `rrStream` event landing during the await can no longer make the file's `summary` disagree with its `intervals` array. The map entries are never mutated post-insert, so the shallow copy is sufficient.

## Re-verified correctness (unchanged, still sound)

- **`kitBpm` empty-accepted guard** — `meanAcceptedRrMs == null ? null : (60000 / meanAcceptedRrMs).round()` (lines 124-129); no division-by-zero / `double.infinity.round()` path.
- **Field mapping** — all serialized keys map to real public members: `RrAcceptance.{minRrMs,consistencyThreshold,coldStartBeats,medianWindow}`, `SessionPolicy.{warmupDuration,targetDuration,silenceWindow}.inMilliseconds` + `sqiFloor.name`, `RrInterval.{intervalMs,isArtifact}`, `SignalQuality.name`, `MeasurementState.done`.
- **Ownership boundary** — observes `CameraPpgService`'s broadcast streams only; never constructs a `CameraPpgSession`/controller/torch (single-camera-owner invariant, note 01).
- **Imports** — confined to the plan's allow-list; no `flutter_ppg`/`camera` leakage; kit `lib/` untouched.
- **Filename** — `_fileTimestamp` zero-pads all fields, no `intl` dependency, fresh-per-call name (no overwrite).
- **pubspec** — `path_provider: ^2.1.6` added via pub under `dependencies`; no storage permission added.

## Residual non-issues (acceptable for this milestone's scope)

- **`getExternalStorageDirectory()!` null-assert (line 165)** throws on iOS, where the call returns `null`. This milestone is explicitly *Android file export* with an `adb pull` workflow, so Android-only is in scope; noted only so the null-assert isn't later reused on iOS without a `getApplicationDocumentsDirectory()` fallback.
- **Post-`done` `tMs` freeze** — after `MeasurementState.done` the stopwatch is stopped but the `rrStream` sub stays live until `stop()`; any trailing beat gets the frozen `done`-moment `tMs`. Negligible given note-21's wall-clock auto-stop, and it does not affect summary correctness.

Neither residual is a defect in the delivered Android scope; both were already flagged as acceptable in review-1 and require no change here.

REVIEW_PASS
