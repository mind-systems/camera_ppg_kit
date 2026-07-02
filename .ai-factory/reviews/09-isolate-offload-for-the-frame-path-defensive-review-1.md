# Code Review: Isolate offload for the frame path (defensive) — Task 1 probe

**Plan:** `.ai-factory/plans/09-isolate-offload-for-the-frame-path-defensive.md`
**Scope of changes:** Task 1 only — the empirical isolate-safety harness. New file `example/lib/isolate_probe/isolate_probe_harness.dart` (246 lines) + a temporary `await runIsolateProbe()` call wired into `example/lib/main.dart`. (The other staged files are planning artifacts, not code.)
**Files read in full:** `isolate_probe_harness.dart`, `example/lib/main.dart`, `example/lib/auto_detect/camera_probe.dart`, `example/lib/auto_detect/log.dart`, `lib/src/api/camera_ppg_session.dart`, `flutter_ppg` 0.2.4 `signal_processor.dart` / `flutter_ppg_service.dart` / `ppg_signal.dart`, `camera` 0.12.0+1 `camera_image.dart`.
**Risk level:** 🟡 Low–Medium — the probe logic is correct for the target devices (Android yuv420 / iOS bgra8888); one robustness issue can brick the example app's launch on an unrelated camera-enumeration failure.

The harness is well-constructed and faithful to the plan: it extracts only the planes `extractRedChannel` reads, ships them as `TransferableTypedData`, reconstructs a 3-element yuv420 planes list with V correctly at index 2 (avoiding the `planes[2]` `RangeError` trap the plan review flagged), passes `format.raw` through so `_asImageFormatGroup` resolves the group, returns only plain sendable values (never `PPGSignal`/`CameraImage`), and surfaces isolate-side errors as data. The transfer-copy semantics are handled correctly (bytes copied at construction, so the recycled native camera buffer is not a use-after-free). All values crossing the port are sendable (`List<double>`, `double`, `int`, `String`, `TransferableTypedData`).

## Findings

### 1. (Medium) A camera-enumeration failure at startup permanently bricks the example app
`main()` is now `async` and does `await runIsolateProbe();` **before** `runApp(...)`. Inside `runIsolateProbe`, the pre-capture region (lines 30–84) is **not** wrapped in try/catch: `enumerateRearCameras()` calls `package:camera`'s `availableCameras()`, which can throw a `CameraException` on a platform-side enumeration failure — this is a known failure mode the kit itself defends against (`camera_ppg_session.dart:576–583` wraps the identical call in try/catch precisely for this). `Isolate.spawn` can also throw.

If any of these throws, the exception propagates out of `runIsolateProbe` → out of the unguarded `await runIsolateProbe()` in `main` → **`runApp` is never reached, and the example app shows a blank/stuck splash on every launch** until the probe call is removed. A diagnostic that runs before `runApp` must never be able to prevent the app from starting.

*Fix:* wrap the probe so failure can't stop `runApp` — either guard the whole `runIsolateProbe` body in try/catch (log + return), or guard the call site: `try { await runIsolateProbe(); } catch (e, st) { ppgLog('[isolate-probe] probe crashed', error: e, stackTrace: st); }`. The latter is the smallest, safest change and covers `Isolate.spawn`/enumeration alike.

### 2. (Low) The probe blocks app launch for ~8–13 s on every startup
Even on the success path, `main` awaits camera init + a fixed `Future.delayed(Duration(seconds: 8))` (+ up to a 5 s handshake timeout) before `runApp`. The example is frozen on the native splash for that whole window on **every** launch while the probe is present. This is intentional and temporary (comments say to remove the call once the verdict is recorded in note 13), so it is not a defect — but it is a sharp foot-gun if the "remove after verdict" step is forgotten. Consider gating it behind a debug flag, or at minimum ensure the removal is tracked as part of closing Task 1. No change strictly required.

### 3. (Low) First-launch camera permission can produce a spurious FAIL verdict
Runtime camera-permission handling is Phase 7 (note 15) and not yet implemented. On a fresh install, `controller.initialize()` triggers the OS permission prompt over the splash; if permission is not granted in time (or is denied), `initialize()`/`startImageStream` fails → caught at line 124 → `signalsReceived == 0` → the harness logs `VERDICT: FAIL`. That FAIL would reflect a permission gap, not an actual isolate-safety failure, and could be misread. Worth a one-line note in the harness/verdict log (or in note 13) that a valid verdict requires camera permission already granted — grant, then re-run. Not a code bug.

### 4. (Nit) Dead `'stop'` branch in the isolate
The isolate's `isolateReceivePort.listen` handles a `'stop'` string by closing `imageStreamCtrl`, but the main side never sends `'stop'` — teardown relies solely on `isolate.kill(priority: Isolate.immediate)` in the `finally`. That is correct and safe for a throwaway probe (kill reclaims the isolate wholesale, so the in-isolate close-before-cancel ordering isn't needed here), but the `'stop'` branch is unreachable and slightly misleading given the real kit must preserve that ordering. Harmless; flagging only so it isn't copied into the production `frame_isolate.dart` (Task 4) under the assumption that `kill` alone suffices there.

## Notes (verified, not issues)
- **yuv420 plane-index preservation is correct.** The 3-element rebuild (`[Y, placeholder, V]`) puts V at index 2, and `_extractRedFromYUV420` reads only planes 0 and 2 — the placeholder at index 1 is never read. The placeholder carries a non-null `bytesPerRow` (`y.bytesPerRow`) so `Plane._fromPlatformData`'s `bytesPerRow as int` cast succeeds.
- **`defaultTargetPlatform` resolves inside the spawned isolate.** `CameraImage.fromPlatformData` → `_asImageFormatGroup` reads `defaultTargetPlatform`, which derives from `Platform.operatingSystem` (works in any isolate) and needs no `WidgetsBinding`. On-device Android/iOS resolution is correct.
- **A yuv420 frame with <3 planes** (`image.planes[2]`) throws in the main-isolate frame callback, but it is inside the `try` around `.send()` (line 108–112), so it is caught and logged per frame — no crash. Standard Android `YUV_420_888` always has 3 planes.
- **No `flutter_ppg`/`camera` types cross the port** — `SignalQuality` is sent as `.name` (String), matching the kit's boundary rule.
