# Code Review: Signal-based camera auto-detect (round 1)

**Plan:** `.ai-factory/plans/01-signal-based-camera-auto-detect.md`
**Scope reviewed:** all staged code changes (`git diff HEAD`) — `example/lib/auto_detect/*`, `example/lib/main.dart`, `example/test/widget_test.dart`, Android manifest, iOS Info.plist, `example/pubspec.{yaml,lock}`.
**Risk level:** 🟡 Medium — the design matches the plan and is architecturally clean, but there is one defect that will fail `flutter test`, and one behavioral defect where the documented warm-up does not actually skip frames.

The kit `lib/` barrel was correctly left untouched — all work is confined to `example/`, honoring the spike scope.

---

## High

### H1 — The widget test will fail: `availableCameras()` runs in `initState` with no plugin and no guard
`AutoDetectScreen.initState()` calls `_enumerate()` → `enumerateRearCameras()` → `availableCameras()` (`auto_detect_screen.dart:34`, `camera_probe.dart:35`). The new widget test pumps the real `CameraPpgKitExampleApp` (`widget_test.dart:9-10`):

```dart
await tester.pumpWidget(const CameraPpgKitExampleApp());
expect(find.textContaining('Place a finger'), findsOneWidget);
```

Under `flutter test` there is no registered camera platform, so `availableCameras()` rejects (a `MissingPluginException` / null-channel error). `_enumerate()` has **no `try/catch`** and the future is fire-and-forgotten from `initState`, so the rejection escapes into the test zone. `flutter_test` reports uncaught async errors as test failures — the suite fails even though the `find.textContaining` assertion itself would pass (the guidance text renders synchronously before the future settles).

This contradicts the plan's "Testing: no" intent in practice: a test *was* modified and now ships red. Fix options (either is fine):
- Wrap the enumeration in `try/catch` in `_enumerate()` (also fixes L3) and/or gate it so a thrown `availableCameras()` leaves a clean "no cameras" state; **and**
- In the test, set a mock method-channel handler for the `plugins.flutter.io/camera_android`/`camera_avfoundation` `availableCameras` call, or assert on a widget that does not depend on the plugin.

At minimum the test must pass under `flutter test` or be removed.

---

## Medium

### M1 — Warm-up frames are not skipped; they are buffered and replayed into the count
In `detectCoveredCamera` (`coverage_detector.dart:69-86`):

```dart
service = FlutterPPGService(config: cfg);
final signals = service.processImageStream(imageStreamCtrl.stream); // async* — lazy
await Future.delayed(warmUp);                                        // nothing listens yet
...
sub = signals.listen((signal) { framesSeen++; if (covered(...)) coveredCount++; });
await Future.delayed(dwell);
```

`processImageStream` is an `async*` generator: it does not begin consuming `imageStreamCtrl.stream` until `.listen` is attached (after the warm-up delay). `imageStreamCtrl` is a **non-broadcast** `StreamController`, so every frame `controller.startImageStream` pushes during the 400 ms warm-up is **buffered**, then delivered in a burst the instant `sub` attaches.

Consequences:
- The warm-up does **not** discard exposure-/torch-settling frames as the doc comment (`coverage_detector.dart:72`) and the plan claim — those frames are counted in `framesSeen`/`coveredCount`.
- `framesSeen` is inflated beyond the intended "~21 frames over the 700 ms dwell" budget (≈ warm-up backlog + live dwell frames).
- The burst replay corrupts `flutter_ppg`'s internal `FrameRateDetector` timing for this controller (not used by the coverage decision here, but it makes the detector's FPS meaningless and will mislead the next milestone if copied).

Practical impact on the covered/not-covered verdict is low when the finger is genuinely present (early frames are still red-saturated), but the behavior diverges from intent and the recorded fractions are not what the panel implies. To actually skip warm-up, attach the listener immediately and ignore frames until a `warmUp` deadline (e.g. capture a start time / `Stopwatch` and only count once elapsed), rather than delaying the `listen`.

---

## Low / Minor

### L1 — Null-assertion in the image-stream callback can throw after teardown nulls the variable
`coverage_detector.dart:62-66`:

```dart
controller.startImageStream((img) {
  if (!imageStreamCtrl!.isClosed) { imageStreamCtrl.add(img); }
});
```

The closure captures the **variable** `imageStreamCtrl`, which teardown sets to `null` (`:112`, `:131`). `stopImageStream()` is awaited first (`:179-183`), so the window is small, but if the camera delivers a late frame after the variable is nulled, `imageStreamCtrl!` throws a null-check error on the platform callback path. Use `imageStreamCtrl?.isClosed != true` (and `imageStreamCtrl?.add(img)`), or don't null the local — the captured reference plus `isClosed` guard is enough.

### L2 — A single `CameraException` aborts the entire round-trip instead of trying the next rear camera
In the `on CameraException` branch (`:119-145`) any init/torch failure on one camera returns `cameraError` immediately, so later rear lenses are never probed. On an iOS multi-lens device, one lens failing to open/initialize would prematurely fail the whole detection. This matches the plan's wording ("wrap into `cameraError` and return"), so it is not a deviation — but `continue`-ing to the next camera and only failing if *all* error out would be more robust. Flagging for the productionization phase (note 08).

### L3 — Enumeration has no error handling; spinner can hang on failure
If `availableCameras()` throws on a real device, `_enumerate()` (`auto_detect_screen.dart:37-45`) leaves `_enumerating = true` forever (spinner never clears) and the error is unhandled. A `try/catch` that sets `_enumerating = false` and surfaces an empty/error state closes this (and resolves H1's test path too).

### L4 — `dwellCompleter` is effectively dead code
`coverage_detector.dart:78-87`: nothing awaits `dwellCompleter`; its only effect is the `isCompleted` guard suppressing counting in the brief window between `complete()` and `sub.cancel()`. Since `await Future.delayed(dwell)` already bounds the window and teardown cancels the subscription, the completer can be removed for clarity.

### L5 — `framesSeen == 0` silently yields "not covered"
`coverage_detector.dart:89`: if no `PPGSignal` is emitted during the dwell (slow device, processing lag), `fraction = 0.0` → not covered, indistinguishable from "finger absent." Acceptable for the spike, but worth surfacing a distinct "no frames" diagnostic so the device-support matrix (note 03) isn't misled.

---

## Positive Notes

- Scope is correctly confined to `example/`; the kit barrel and `lib/src/` are untouched, as the plan mandates. Clean handoff to Phase 5.
- C1 from the plan review was respected — finger-presence is inlined from the exported `PPGConfig` (`coverage_detector.dart:29-32`), no reach into `flutter_ppg`'s private `src/`.
- Sequential single-controller round-trip with mandatory teardown between cameras (`_tearDown`) correctly honors the "cameras cannot be opened concurrently" constraint; each loop iteration declares fresh locals, so there is no controller leak across iterations.
- Typed `CoverageOutcome` / `AutoDetectError` result; the detector never throws out to the caller. Matches the "typed states, not exceptions" rule.
- Coarse rebuilds only (no per-frame `setState`), addressing the FPS-starvation risk.
- `uses-feature ... camera.flash` is correctly `required="false"`; iOS `NSCameraUsageDescription` is present and descriptive; deps added via `pubspec` with `direct main` in the lock (Task 2 satisfied).
- Permission-denial mapping (`code.contains('permission') || code.contains('access')`, `:135-136`) reasonably catches the `CameraAccessDenied` codes on both platforms.

---

## Verdict

Design is sound and on-spec, but **not ready as written**: H1 ships a failing `flutter test`, and M1 means the warm-up does not do what it documents. Fix H1 (guard enumeration and/or fix the test) and M1 (skip warm-up by time, not by deferring `listen`); L1–L5 are optional polish, with L1 worth doing since it is a latent runtime throw.

Changes requested — not approving this round.
