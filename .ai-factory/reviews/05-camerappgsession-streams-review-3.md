# Code Review 3: CameraPpgSession + streams (05)

**Reviewed:** `git diff HEAD` — `lib/src/api/camera_ppg_session.dart` (now 545 lines), `lib/src/api/rr_diff.dart`, `lib/src/util/nlog.dart`, `test/camera_ppg_session_rr_conversion_test.dart`, `lib/camera_ppg_kit.dart`.
**Read in full:** all changed files + `lib/src/models/*`, `flutter_ppg` 0.2.4 `flutter_ppg_service.dart` / `ppg_signal.dart`, example ports.
**Round:** 3 (verifies the review-2 Finding-1 fix; re-checks the concurrency machinery end-to-end).
**Overall:** 🟢 Pass. The only change since round 2 is the outer-`finally` guard `if (!lockedAndStreaming && !stale()) await _release();` — precisely the review-2 Finding-1 fix. I re-traced the start→stop→start interleaving and it is resolved with no regression. No blocking, correctness, or security issues remain in this milestone's scope.

---

## Verification of the round-2 Finding-1 fix

The abandoned-`start()`-clobbers-a-newer-`start()` defect is fixed. Re-traced the exact round-2 repro:

1. `start()` #1: `_running = true`, captures `generation = 0`, suspends on `await _enumerateRearCameras()`.
2. `stop()`: `_release()` → `_running = false`, `_generation = 1`, state `idle`.
3. `start()` #2: sees `_running == false` → proceeds, captures `generation = 1`, suspends.
4. `start()` #1 resumes: `stale()` (`1 != 0`) true → returns `null` → outer `finally`: `!lockedAndStreaming` (true) `&& !stale()` (**false**) → **skips `_release()`**. Its own local handles were already torn down by the inner `finally`. No shared state touched. ✅
5. `start()` #2 continues and owns the session uncontended. ✅

No regression on the other paths:
- **Genuine uncontended failure** (e.g. no rear camera, `CameraException`): `stale()` is false → outer `finally` still runs `_release()`, correctly resetting `_running`/state to `idle`. ✅
- **"Genuine failure + concurrent start#2"** is unreachable: for start#2 to begin, `_running` must be false, which only a concurrent `stop()`/`dispose()` (`_release()` → `_generation++`) produces — which makes start#1 stale, so it correctly skips `_release()`. ✅
- **No stuck-`true` `_running`:** success keeps it true (owner live); uncontended failure clears it; stale abandon leaves it to the current owner. ✅
- **No double-dispose:** local handles torn down by the inner `finally`; instance fields are null on every non-promoted path, so `_release()` in the outer `finally` no-ops on handles while resetting flags. Promotion (lines 229–232) has no `await` before it, so `stop()`/`dispose()` cannot interleave between the final `stale()` check and promotion. ✅

---

## Verified correct (unchanged, re-confirmed)

- **Barrel boundary:** `import ... hide SignalQuality`; quality via `SignalQuality.fromSnr(snr)`, never `PPGSignal.quality`; no `flutter_ppg`/`camera` type in any public signature; `debugSignalStream` is `List<double>`.
- **Teardown invariant** (`_tearDownHandles`, used by `_release`, `_probeCameraCoverage`, and start's abandon path): stopImageStream → **close bridge before cancel** (the `async*` `await for` deadlock) → cancel sub → `service.dispose()` (unawaited `void`, correct) → torch off → dispose controller.
- **Permission path:** `initialize()` throwing `CameraAccessDenied` inside a probe propagates through its `finally` to `_lockCoveredCamera`'s `on CameraException` → `fromCameraErrorCode` → surfaced as a typed value.
- **`diffNewIntervals`** edge cases (empty/growing/sliding/no-overlap/rounding) match the unchanged test suite; longest-overlap-first is the safe heuristic.
- **`FingerPresence.fromRawIntensity`** band equivalent to the example discriminator; NaN→absent guarded.
- **`_onSignal`** guards every `add` with `isClosed`; `_setState` dedupes.

---

## Non-blocking, out-of-scope (carried; explicitly deferred by the plan — no action this milestone)

- **`diffNewIntervals` can re-emit duplicates** when `flutter_ppg`'s per-frame outlier filter drops a non-tail interval (breaking tail/head alignment → returns whole `current`). Documented in `rr_diff.dart` and the plan; real dedup + artifact detection is the **Phase-6 acceptance gate (note 12)**. This is the deliberate "minimal passthrough" behavior, not a defect against this milestone.
- **Micro-race on stale abandon:** if `start()` #1 wired its `_sub` and then goes stale, a frame buffered before `stopImageStream()` could fire `_onSignal` once during teardown, touching shared instance state (`_lastRrIntervals`, quality/debug controllers). Impact is negligible — the buffer isn't full so `rrIntervals` is empty (no RR emitted), and the owning `start()` resets `_lastRrIntervals` on promotion. Not reachable in the normal awaited-usage path; proper subscription-ownership fencing belongs to **Phase-9 lifecycle hardening (note 17)**.
- **`qualityStream` emits ~24×/s undeduped** (state is deduped) — matches the plan; a directly-bound UI can `distinct()`.

---

## Recommendation

The two blocking findings from rounds 1 and 2 are both resolved and re-verified against the actual control flow. The remaining items are behavior the plan explicitly defers to Phases 6 and 9. Nothing actionable remains in this milestone's scope.

REVIEW_PASS
