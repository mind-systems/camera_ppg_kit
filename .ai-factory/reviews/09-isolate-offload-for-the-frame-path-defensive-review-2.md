# Code Review (round 2): Isolate offload for the frame path (defensive) — full milestone

**Plan:** `.ai-factory/plans/09-isolate-offload-for-the-frame-path-defensive.md`
**Scope:** the complete milestone, implemented across commits `aa93b0f`..`e3fabe4`. Working tree is clean except the plan `.json` (bookkeeping). Task 1's temporary probe harness and its `main.dart` call were correctly removed after the verdict was recorded (review-1's Medium finding — the startup brick risk — is fully resolved by deletion).
**Files read in full:** `lib/src/processing/frame_message.dart`, `lib/src/processing/frame_isolate.dart`, `lib/src/api/camera_ppg_session.dart`, `test/frame_transfer_test.dart`, plus the note-13 verdict and ARCHITECTURE.md dependency-rule exception.

Overall this is a clean, well-reasoned implementation. Variant (a) is confirmed on-device (note 13); the yuv420 3-plane reconstruction trap the plan review flagged is handled correctly and locked by a unit test; the close-before-cancel teardown invariant is faithfully mirrored *inside* the isolate; errors cross the port as `SignalMessage.error` data (never thrown); only sendable values cross; the `_generation`/`stale()` abandon discipline is preserved across the new `await FrameIsolate.spawn()`; and the abandoned-isolate path tears the isolate down. Two findings below — one real resource leak on an error path, one defensive gap.

## Findings

### 1. (Medium) `FrameIsolate.spawn` leaks the spawned isolate + `ReceivePort` on handshake timeout
`frame_isolate.dart:167–176`:

```dart
final isolate = await Isolate.spawn(_frameIsolateEntrypoint, fromIsolate.sendPort, ...);
final toIsolate = await handshake.future.timeout(
  const Duration(seconds: 5),
  onTimeout: () => throw StateError('frame isolate handshake timed out'),
);
```

When the handshake times out, `onTimeout` throws — but `isolate` is already **live** (spawned successfully) and `fromIsolate` is an **open** `ReceivePort`. The throw propagates out of `spawn()` without `isolate.kill(...)` or `fromIsolate.close()`, so a wedged/slow spawn strands a zombie isolate (holding a `FlutterPPGService`) plus an open port. In `start()` the `StateError` is caught by the generic `catch` (`camera_ppg_session.dart:353`) → returns `cameraUnavailable`; the inner `finally` disposes the camera + torch (so note-13's "leaked isolate keeps the torch warm" guard is *not* violated — torch is on the main isolate and is turned off), but the background isolate and port are never reclaimed. Repeated `start()` retries after timeouts accumulate zombies.

Handshake timeout is low-probability (spawn is normally fast), but it is a reachable error path on a heavily loaded device, and it is exactly the kind of leak this milestone's Guards section is meant to prevent.

*Fix:* wrap the handshake await so a timeout (or any failure) cleans up before rethrowing:
```dart
try {
  final toIsolate = await handshake.future.timeout(const Duration(seconds: 5));
  ...
} catch (_) {
  isolate.kill(priority: Isolate.immediate);
  fromIsolate.close();
  rethrow;
}
```

### 2. (Low) Measurement `startImageStream` callback has no guard around `frameMessageFromCameraImage`
`camera_ppg_session.dart:309–311`:

```dart
controller.startImageStream((img) {
  fi.sink(frameMessageFromCameraImage(img));
});
```

`frameMessageFromCameraImage` reads `image.planes[2]` for the yuv420 branch. On a conformant `YUV_420_888` stream there are always 3 planes, so this is safe on the tested hardware — but if a device/plugin ever delivers a frame whose actual layout doesn't match the configured group (e.g. a bi-planar/NV21 frame with `<3` planes), `planes[2]` throws a `RangeError` **inside the camera plugin's UI-isolate callback**, uncaught, once per frame.

Note the asymmetry: the isolate-side reconstruction *is* defensively wrapped (`frame_isolate.dart:251–256`, errors→`SignalMessage.error`), and the probe path guards `isClosed`. Previously, malformed frames were absorbed by `flutter_ppg`'s internal `try { extractRedChannel } catch { continue }`; moving plane extraction into the raw callback removes that safety net for the plane-access step. A `try/catch` that logs and drops the frame would restore the kit's "never crash on a bad frame" posture and match finding-style errors-as-data handling. Not observed on the A70; low severity because it only bites nonconformant frame layouts.

## Notes (verified, not issues)
- **No new frame-delivery backpressure regression.** `sink()` is fire-and-forget, but the pre-isolate path (`imageStreamCtrl.add`) was equally unbounded; the comment (`frame_isolate.dart:188–190`) is honest about it.
- **`dispose()` is effectively idempotent** even though it's documented as call-once: a second call sends to a dead port (dropped), awaits an already-completed `_stopAck`, re-kills (no-op), and re-closes an already-closed controller (no-op). `_release()` nulls `_frameIsolate` before teardown, so it isn't double-disposed in normal flow.
- **Stop-ack path is independent of the signal subscription.** `_tearDownHandles` cancels `signalSub` before `frameIsolate.dispose()`, but the `_stoppedSentinel` is delivered via `FrameIsolate`'s own `fromIsolate.listen`, not the signals stream — so cancelling the subscription can't lose the ack. Correct.
- **In-isolate close-before-cancel is correct and can't hang unboundedly.** `await imageStreamCtrl.close()` drains buffered frames then ends `processImageStream`'s `await for`; frames stop being sent before the stop sentinel (`stopImageStream` runs first in `_tearDownHandles`), and the 2 s ack timeout + immediate kill is the backstop.
- **No early-signal loss in practice.** The broadcast `_signalsController` drops events with no listener, but frames only start at `startImageStream` (line 309) and `.listen` (line 313) attaches synchronously right after with no intervening `await`, so the first frame callback fires after the listener exists; warm-up discards early ticks regardless.
- **Test is meaningful and correct.** It exercises the real `CameraImage.fromPlatformData` path, asserts the yuv420 rebuild is 3 planes with V at index 2 (locking the Android trap), handles the test-env `defaultTargetPlatform` default with an explicit iOS override for bgra8888, and replicates the `extractRedChannel` formula inline (correctly noting it's not exported). bgra8888 is source/test-confirmed but not device-confirmed (no iOS hardware) — honestly recorded in note 13.
- **Boundary discipline held.** `SignalMessage` carries exactly the five fields `_onSignal` consumes; `PPGSignal.quality` is dropped (`SignalQuality` is re-derived from SNR); no `flutter_ppg`/`camera`/isolate type crosses the public surface; ARCHITECTURE.md records the `frame_isolate.dart` dependency-rule exception.

## Verdict
Finding 1 (isolate/port leak on handshake timeout) is worth fixing before this is considered done — it's a small, localized change. Finding 2 is a low-severity defensive hardening. Neither blocks the happy path, which is correct and well-tested.
