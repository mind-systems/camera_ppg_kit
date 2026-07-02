# Code Review 2: CameraPpgSession + streams (05)

**Reviewed:** `git diff HEAD` — `lib/src/api/camera_ppg_session.dart` (now 539 lines, reworked since review 1), `lib/src/api/rr_diff.dart`, `lib/src/util/nlog.dart`, `test/camera_ppg_session_rr_conversion_test.dart`, `lib/camera_ppg_kit.dart`.
**Read in full:** all of the above + `lib/src/models/*`, `flutter_ppg` 0.2.4 `flutter_ppg_service.dart` / `ppg_signal.dart`, example ports.
**Round:** 2 (verifies the review-1 Finding-1 fix and re-checks the new concurrency machinery).
**Overall:** 🟢 Solid. Review-1 Finding 1 (stop/dispose during in-flight `start()`) is now genuinely addressed with a `_generation` epoch + staleness re-checks after every await, local handles promoted to instance fields only when fully wired, and a shared `_tearDownHandles`. The teardown, boundary discipline, and failure-path `_running` clearing remain correct. One new reentrancy defect was introduced by that fix; `rr_diff`/tests are unchanged.

---

## Findings

### 1. (Medium, correctness/concurrency) An abandoned `start()` calls the global `_release()` and clobbers a newer `start()` that already owns the session

The Finding-1 fix makes a stale `start()` return `null` and, in its **outer** `finally`, unconditionally run `await _release()` (line 258–262: `if (!lockedAndStreaming) await _release();`). But `_release()` is a *global* reset — it clears `_running`, bumps `_generation`, and sets state `idle`. Because `stop()` clears `_running` while the first `start()` is still suspended, a **second** `start()` can legitimately begin before the first resumes, and the first's abandon-path `_release()` then mutates state the second call owns.

**Repro (start → stop → start, none awaited):**
1. `start()` #1: `_running = true`, captures `generation = 0`, suspends on `await _enumerateRearCameras()`.
2. `stop()`: `_release()` → `_running = false`, `_generation = 1`, state `idle`.
3. `start()` #2: sees `_running == false` → proceeds, `_running = true`, captures `generation = 1`, suspends on enumeration.
4. `start()` #1 resumes: `stale()` (`1 != 0`) → returns `null` → **outer `finally` runs `_release()`** → `_running = false`, `_generation = 2`, state `idle`.
5. `start()` #2 resumes: `stale()` (`2 != 1`) → returns `null`, nothing streaming.

Result: `start()` #2 **silently returns `null` (its success value) while no measurement is running**, and `_running` is left `false`. The caller believes it started a session; it did not. (It is not a permanent lock — a subsequent `start()` works — but it is a silent no-op of a legitimate call.)

Root cause: the abandon path should tear down only *its own* local handles (the **inner** `finally` at 238–251 already does exactly this), not invoke the session-global `_release()`. `_release()` is correct for a genuine failure of a call that still owns the session, but wrong once a concurrent `stop()` has already released and a newer `start()` may have taken ownership.

**Fix:** gate the outer `finally` on ownership, e.g. `if (!lockedAndStreaming && !stale()) await _release();`. On a stale abandon, `stale()` is true → skip the global reset (the concurrent `stop()` already did it, and the local handles are torn down by the inner `finally`); on a genuine failure with no concurrent teardown, `stale()` is false → `_release()` still runs and resets `_running`/state as today. Verify: (a) genuine `CameraException`/unexpected-error path still resets when uncontended; (b) the two pre-inner-`try` stale returns (lines 137–140, 149–152) also skip `_release()` under the same guard.

### 2. (Low, accepted scope — carried from review 1) `diffNewIntervals` can re-emit already-sent intervals as duplicates

Unchanged from review 1. `flutter_ppg` re-runs `filterOutliersWithStats` each frame (`flutter_ppg_service.dart:265`) and can drop a non-tail interval; when that breaks previous-tail/current-head alignment, `diffNewIntervals` returns the whole `current` and re-emits beats already sent. E.g. `previous = [800, 900, 750]` → `current = [800, 750, 810]` yields `[800, 750, 810]`, re-emitting `800`/`750`. Downstream HRV double-counts. Explicitly deferred to the Phase-6 acceptance gate (note 12); no change required here.

### 3. (Low, informational) A stale `stop()` may leave a *probe* camera + torch on for up to ~1.1 s after it returns

If `stop()`/`_release()` runs while `start()` is inside `_probeCameraCoverage`'s `Future.delayed(_probeWarmUp + _probeDwell)`, `_release()` only touches the (still-null) instance fields — the probe's *local* controller keeps the torch on until its own `finally` fires when the dwell completes (~1.1 s later). No permanent leak (the probe self-cleans and `start()` then abandons via `stale()`), but `await stop()` can return while a probe torch is briefly still lit. Acceptable for this milestone; full background/lifecycle robustness is Phase 9 (note 17).

### 4. (Low, informational — carried) `qualityStream` emits every frame undeduped

Unchanged from review 1: `_onSignal` adds a `SignalQuality` per signal (~24/s) with no `distinct()`, while `stateStream` is deduped. Matches the plan; a directly-bound UI rebuilds ~24×/s. Non-blocking.

---

## Verified correct (no action)

- **Finding-1 fix is sound for the common case:** `_generation` captured at entry, re-checked after enumeration, probe, `initialize()`, torch/lock setup, and stream wiring; handles held in locals and promoted to fields (lines 229–232) only after the last stale check with **no await** before promotion, so `stop()`/`dispose()` cannot interleave in the promote gap. `dispose()` during in-flight `start()` is handled the same way.
- **`_tearDownHandles`** preserves the spike invariant everywhere (stopImageStream → **close bridge before cancel** → cancel sub → `service.dispose()` (unawaited `void`, correct) → torch off → dispose controller); no double-dispose since local handles are torn down by the inner `finally` and instance fields are null on failure paths.
- **Barrel boundary:** `hide SignalQuality`, `SignalQuality.fromSnr(snr)` (never `PPGSignal.quality`); no `flutter_ppg`/`camera` type in any public signature; `debugSignalStream` stays `List<double>`.
- **Permission path:** `initialize()` throwing `CameraAccessDenied` in `_probeCameraCoverage` propagates through its `finally` to `_lockCoveredCamera`'s `on CameraException` → `fromCameraErrorCode` → returned as a value.
- **`diffNewIntervals` edge cases** (empty/growing/sliding/no-overlap/rounding) match the test suite; longest-overlap-first is the safe heuristic.
- **`FingerPresence.fromRawIntensity`** band is equivalent to the example's coverage discriminator; NaN→absent guarded.
- **No stuck-`true` `_running`:** set true only at entry; a successful start keeps it true (session live), every fail/abandon path routes through `_release()` today (Finding 1 changes only the *abandon* sub-case).

---

## Recommendation

Fix **Finding 1** (gate the outer-`finally` `_release()` on `!stale()` so an abandoned `start()` stops resetting shared state owned by a newer call) — it is a reachable silent no-op under rapid start→stop→start. Findings 2–4 are accepted-scope caveats already contemplated by the plan / deferred to later phases. The rest of the implementation, including the bulk of the review-1 Finding-1 fix, is correct.
