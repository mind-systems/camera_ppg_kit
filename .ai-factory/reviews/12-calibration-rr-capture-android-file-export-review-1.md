# Code Review: Calibration RR-capture + Android file export

**Reviewed:** `git diff HEAD` / `git status`
**Changed code files:**
- `example/lib/calibration/calibration_recorder.dart` (new)
- `example/pubspec.yaml` / `example/pubspec.lock` (adds `path_provider`)

(The `.ai-factory/**` artifacts — plan, plan-review, planner json — are process files, not code, and are not reviewed for runtime behavior.)

## Summary

The implementation faithfully follows the plan and spec note 20. It observes `CameraPpgService` (never owns a session/controller/torch — single-camera-owner invariant intact), buffers every `RrInterval` with a monotonic `Stopwatch` clock and latest SQI, and writes a self-describing JSON per `save()`. All serialized fields map to real, correctly-named public members verified against the kit source (`RrInterval.intervalMs/isArtifact`, `RrAcceptance.{minRrMs,consistencyThreshold,coldStartBeats,medianWindow}`, `SessionPolicy.{warmupDuration,targetDuration,silenceWindow,sqiFloor}` as `Duration`/enum, `SignalQuality.name`, `MeasurementState.done`). The `kitBpm` empty-accepted guard (flagged in plan-review) is correctly implemented — `meanAcceptedRrMs == null ? null : (60000 / meanAcceptedRrMs).round()` — so the `double.infinity.round()` crash is avoided. `path_provider` is added via pub, not hand-edited; no storage permission added.

**No critical or blocking bugs found.** The findings below are minor robustness/edge-case issues on paths outside the documented happy flow.

## Findings

### 1. `start()` called twice without an intervening `stop()` leaks three subscriptions (Minor)

`example/lib/calibration/calibration_recorder.dart:47-80` — `start()` clears buffers and unconditionally reassigns `_rrSub`/`_qualitySub`/`_stateSub` without cancelling any existing subscriptions first. If `start()` is invoked a second time before `stop()`, the previous three `StreamSubscription`s are overwritten and leak (they keep mutating `_latestQuality`/`_done` against a discarded run), and the buffer is silently reset mid-run.

`CameraPpgService.startMeasurement()` no-ops on a double-tapped Start (its `_measuring` guard), but the recorder has no matching guard, so a double-tapped Start on the note-21 screen would leave the service measuring on its original session while the recorder resets its buffer and orphans its first subscription set. Defensive fix: call `stop()` (or cancel the three subs) at the top of `start()`, or add an early return when already recording. Low severity given the documented one-start-per-run contract, but the screen wiring in note 21 should either rely on this guard or add its own.

### 2. Calling `save()` while still recording can desync `summary` vs `intervals` (Minor)

`example/lib/calibration/calibration_recorder.dart:87-160` — `save()` computes the summary counts (`_records.length`, `accepted`, means) synchronously at the top, then `await getExternalStorageDirectory()`, then serializes. `json['intervals']` holds a **live reference** to `_records`. If subscriptions are still active (i.e. `save()` is called before `stop()`), an `rrStream` event delivered during the `await` window appends to `_records`, so the serialized `intervals` array gains an entry the pre-await `summary.totalIntervals`/`acceptedIntervals` don't count — the file's own summary would disagree with its interval list.

The documented flow is `stop()` → optional count entry → `save()`, under which the streams are already cancelled and this cannot happen. Still worth hardening: snapshot `_records` (e.g. `List.of(_records)`) into the JSON, or assert/require `stop()` before `save()`. Low severity — contract-dependent.

### 3. `getExternalStorageDirectory()!` null-assert throws on iOS (Minor / out of scope)

`example/lib/calibration/calibration_recorder.dart:152` — `baseDir!` will throw on iOS, where `getExternalStorageDirectory()` returns `null`. This milestone is explicitly "Android file export" with an `adb pull` workflow, so this is acceptable scope, but the recorder is otherwise platform-agnostic; if it is ever reused on iOS it needs a `getApplicationDocumentsDirectory()` fallback. Flagging so the null-assert isn't mistaken for a platform-safe call later.

### 4. RR intervals arriving after `MeasurementState.done` get a frozen `tMs` (Minor / edge)

`example/lib/calibration/calibration_recorder.dart:63-77` — on `done` the stopwatch is stopped but the `rrStream` subscription stays live until `stop()`. Any interval emitted between `done` and the screen calling `stop()` is still appended, but with a frozen (stale) `_stopwatch.elapsedMilliseconds` for its `tMs`, so post-`done` beats would share the timestamp of the `done` moment. In practice note 21 auto-stops at the wall-clock target and the session emits little/nothing after `done`, so this is a negligible edge, but the `tMs` monotonicity assumption technically breaks for those trailing beats.

## Verified Non-Issues

- **`kitBpm` division-by-zero / infinity** — correctly guarded via the `meanAcceptedRrMs == null` short-circuit (`accepted.isEmpty ? null`); no `60000 / 0` path.
- **`isArtifact == false` filter** — records store a real `bool`, so the equality filter and `artifactCount = total - accepted` arithmetic are sound.
- **Broadcast stream re-subscription** — `CameraPpgService`'s three streams are `.broadcast()`; the recorder subscribing alongside the service's internal fan-in raises no "already listened to" error.
- **Import boundary** — only `dart:async/convert/io`, the kit barrel, `path_provider`, the example log helper, and the service are imported; no `flutter_ppg`/`camera` leakage, kit `lib/` untouched.
- **Filename timestamp** — `_fileTimestamp` zero-pads all fields manually; no `intl` dependency added, and the fresh-per-call name means no overwrite.
- **pubspec** — `path_provider: ^2.1.6` added under `dependencies`; lockfile transitive additions (ffi, jni, etc.) are the expected `flutter pub add` fan-out.
