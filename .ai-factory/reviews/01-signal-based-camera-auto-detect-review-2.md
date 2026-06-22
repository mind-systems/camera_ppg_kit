# Code Review: Signal-based camera auto-detect (round 2)

**Plan:** `.ai-factory/plans/01-signal-based-camera-auto-detect.md`
**Scope reviewed:** all staged code changes (`git diff HEAD`) re-read in full, focusing on deltas since review round 1 — `coverage_detector.dart`, `auto_detect_screen.dart`, `test/widget_test.dart`.
**Risk level:** 🟢 Low — every round-1 finding is correctly resolved; no new defects introduced. Residual items are by-spec spike limitations, not blockers.

---

## Round-1 findings — verification

### H1 (High) — widget test failed under `flutter test` → **RESOLVED**
`_enumerate()` now wraps `enumerateRearCameras()` in `try/catch` (`auto_detect_screen.dart:39-51`), clearing the spinner and swallowing the `MissingPluginException` raised when no camera plugin is registered on the test host. The async rejection no longer escapes into the test zone. The test (`widget_test.dart`) asserts the synchronously-rendered guidance text and then `await tester.pump()` drains the pending enumeration microtask, leaving a clean zone. The suite will now pass. ✓

### M1 (Medium) — warm-up frames buffered & replayed → **RESOLVED**
The listener is now attached **immediately** (`coverage_detector.dart:83`), and warm-up frames are discarded by `Stopwatch` elapsed time rather than by deferring `listen`:
```dart
final stopwatch = Stopwatch()..start();
sub = service.processImageStream(imageStreamCtrl.stream).listen((signal) {
  final elapsed = stopwatch.elapsed;
  if (elapsed < warmUp) return;            // discard settling frames
  if (elapsed >= warmUp + dwell) return;   // window closed
  framesSeen++; if (covered(signal.rawIntensity)) coveredCount++;
});
await Future.delayed(warmUp + dwell);
```
I verified there is **no `await` between `startImageStream` (`:66`) and `.listen` (`:83`)** — only synchronous statements — so the event loop never turns in that window and no frame can be delivered to the non-broadcast controller before a reader is attached. Buffering/burst-replay is eliminated, the warm-up genuinely skips settling frames, and `framesSeen` reflects only the dwell window. ✓

### L1 (Low) — null-assertion in stream callback → **RESOLVED**
Callback now uses `imageStreamCtrl?.isClosed != true` and `imageStreamCtrl?.add(img)` (`:67-68`), so a late frame after teardown nulls the variable is a no-op instead of a null-check throw. ✓

### L3 (Low) — enumeration spinner could hang on throw → **RESOLVED**
`_enumerate()`'s `catch` sets `_enumerating = false` (`:50`), so the spinner always clears. ✓

### L4 (Low) — dead `dwellCompleter` → **RESOLVED**
Replaced entirely by the `Stopwatch` window logic. ✓

---

## Residual non-blocking notes (no change required)

- **L2 (carried over, by-spec):** a `CameraException` on any single rear camera still returns `cameraError` and aborts the whole round-trip (`:125-151`), rather than continuing to the next lens. This matches the plan's explicit "wrap into `cameraError` and return" instruction and is acceptable for the spike; worth revisiting when this logic is productionized into `CameraPpgSession` (note 08), where trying the next lens before failing would be more robust on multi-lens iOS devices.
- **L5 (carried over, acceptable):** `framesSeen == 0` yields `fraction = 0.0` → "not covered" (`:95`), indistinguishable from finger-absent. Fine for the spike; a distinct "no frames" diagnostic would make the device-support matrix (note 03) clearer.
- **Nitpick:** the `_start()` comment (`auto_detect_screen.dart:62-66`) references a `_probingIndex` variable that does not exist — stale wording from an earlier draft. Harmless; trim when convenient.
- **Minor (timing precision):** warm-up/dwell are measured by *processing* time inside the listener, not frame *capture* time. Because the listener now drains in real time at `ResolutionPreset.low`, processing tracks capture closely, so the boundary error is sub-frame and immaterial. No action.

---

## Positive Notes

- Scope still correctly confined to `example/`; kit barrel and `lib/src/` untouched.
- Teardown remains robust across all exit paths (success, not-covered, `CameraException` during `initialize`/`setFlashMode`, generic catch): `isStreamingImages` / `isInitialized` guards make `_tearDown` safe on partially-constructed controllers, and per-iteration locals prevent controller leaks.
- M1 fix is the correct shape — attach-immediately + time-gate — and the inline comment documents *why* the deferred-listen approach was wrong, which protects the next milestone from regressing it.
- Typed `CoverageOutcome` / `AutoDetectError`, coarse rebuilds, inlined finger-presence from exported `PPGConfig`, and `required="false"` flash feature all remain intact.

---

## Verdict

All round-1 findings (H1, M1, L1, L3, L4) are correctly resolved and no new defects were introduced. Remaining items are by-spec spike limitations and a trivial stale comment — none blocking. Approving.

REVIEW_PASS
