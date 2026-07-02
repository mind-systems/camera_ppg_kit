# Code Review (round 3): Isolate offload for the frame path (defensive) — fix verification

**Plan:** `.ai-factory/plans/09-isolate-offload-for-the-frame-path-defensive.md`
**Scope:** the only code change since round 2 is commit `e820168` ("Fix isolate/port leak on handshake timeout and guard the frame callback"), which addresses both round-2 findings. Working tree is clean except the plan `.json` (bookkeeping).
**Files reviewed:** full diff of `e820168`; `frame_isolate.dart` and `camera_ppg_session.dart` in the surrounding context (unchanged elsewhere since round 2, which was already reviewed in full).

## Round-2 findings — both resolved

### Finding 1 (Medium) — isolate/port leak on handshake timeout → FIXED
`FrameIsolate.spawn` now hoists `Isolate? isolate;` and wraps the spawn + handshake in `try`, with a `catch` that runs `isolate?.kill(priority: Isolate.immediate)` + `fromIsolate.close()` + `await signalsController.close()` before `rethrow`. This correctly reclaims:
- the live isolate when `Isolate.spawn` succeeded but the handshake timed out (`isolate` non-null → killed);
- nothing spurious when `Isolate.spawn` itself threw (`isolate` null → `?.` no-op);
- the open `ReceivePort` and the broadcast controller in every failure case.

The extra `signalsController.close()` (beyond the suggested fix) is a correct, harmless addition — on the failure path the controller is referenced only locally and is never promoted into a returned `FrameIsolate`, so there is no double-close. The `StateError` still propagates to `start()`'s generic `catch` → `cameraUnavailable`, and `_frameIsolate` is never assigned, so no dangling handle remains.

### Finding 2 (Low) — unguarded frame callback → FIXED
The measurement `startImageStream` callback now wraps `fi.sink(frameMessageFromCameraImage(img))` in `try/catch`, logging via `nlog` and dropping the frame. This restores the drop-and-continue posture that `flutter_ppg`'s internal `try { extractRedChannel } catch { continue }` previously provided, now that plane extraction runs ahead of the isolate boundary. A malformed/nonconformant frame layout can no longer throw uncaught inside the raw camera-plugin callback.

## No regressions introduced
- The bare `catch (e)` before `rethrow` in `spawn` is idiomatic (the exception is intentionally re-raised unchanged) and is not flagged by `flutter_lints`.
- Closing an already-open broadcast controller / `ReceivePort` on the failure path cannot throw, so the `catch` cleanup is safe to `await`.
- The happy path (spawn succeeds, handshake completes) is behaviorally identical to the round-2 code that was verified correct; the fix only adds an error-path branch and a per-frame guard.

All other round-2 verifications (boundary discipline, close-before-cancel teardown, `dispose()` idempotency, stop-ack independence, no early-signal loss, the synthetic-frame test locking the yuv420 3-plane trap) remain valid — those files are unchanged.

REVIEW_PASS
