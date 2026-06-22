# Plan: Signal-based camera auto-detect

## Context
Build the Phase-2 spike panel in the example app that, on Start, runs one sequential round-trip over the rear cameras (torch on, short coverage dwell each, most-likely-covered first) and locks the first that reads **covered** via `flutter_ppg` finger-presence — proving whether default-camera + finger-presence is enough before any kit API is committed.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Notes / Constraints (read before implementing)
- This is a **hardware-feasibility spike**, not the production API. The auto-detect logic lives **in the example app** for now; Phase 5 (`note 08`) productionizes it into `CameraPpgSession`. Do **not** add anything under `lib/src/` in this milestone — keep the kit barrel untouched.
- Real device only — torch/camera are absent on simulators/emulators.
- **Cameras cannot be opened concurrently** → the round-trip is strictly sequential: open one `CameraController`, evaluate, **dispose it before opening the next**.
- Lock on **coverage**, not on a confirmed pulse. Coverage discriminator = `flutter_ppg`'s finger-presence, inlined as `rawIntensity` inside `PPGConfig.fingerPresenceMin..fingerPresenceMax` (default 30..250), evaluated across the dwell window. Pulse confirmation is the next milestone's warm-up, not here.
- The finger is placed **before** Start, so this is a one-shot round-trip, never a loop. If no rear sensor reads covered, surface a typed failure and return to idle for retry — the torch flickers only during the single pass.
- Keep state plain (`StatefulWidget` + `setState`) — no Riverpod/go_router yet. The full Riverpod + go_router scaffold is deferred to Phase 9. Keep heavy rebuilds out of the per-frame path (only update aggregate counters, not per-frame).
- Keep resolution low (`ResolutionPreset.low`) to protect FPS. Set an `imageFormatGroup` and verify `flutter_ppg` red-channel extraction works for the chosen format on each platform (iOS `bgra8888`, Android `yuv420`) — a wrong format yields valid frames but garbage intensity (silent failure, not a crash). Flag the result for the device-support matrix (note 03).

## Relevant API facts (verified)
- `camera ^0.12`: `availableCameras() -> List<CameraDescription>` (fields: `name`, `lensDirection`, `sensorOrientation`, and `lensType` — `CameraLensType { wide, telephoto, ultraWide, unknown }`, often `unknown`); `CameraController(desc, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ...)`; `await controller.initialize()`; `await controller.setFlashMode(FlashMode.torch)`; `controller.startImageStream((CameraImage img) {...})`; `await controller.dispose()`. `startImageStream` takes a **callback**, not a `Stream` — bridge it through a `StreamController<CameraImage>`.
- `flutter_ppg 0.2.4`: `FlutterPPGService({PPGConfig config})`; `Stream<PPGSignal> processImageStream(Stream<CameraImage> images)`; `service.dispose()`. `PPGSignal` (exported) exposes `rawIntensity`, `quality` (`SignalQuality.poor|fair|good`), `snr`, `frameRate`, `isFPSStable` — and a real `rawIntensity` on **every** frame (including pre-FPS-stable early frames), so finger-presence works immediately during warm-up + dwell. `PPGConfig` (exported) exposes `fingerPresenceMin`/`fingerPresenceMax` (defaults 30/250).
- **Finger-presence is inlined, not imported.** `SignalQualityAssessor` is **not** re-exported by `flutter_ppg`'s barrel (it lives in the package's `src/` — reaching into it is a private-import anti-pattern and won't resolve cleanly). Replicate its check directly from the exported `PPGConfig`: `bool covered(double raw) => raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax;` — this is exactly what `isFingerPresent` does.
- Logging: copy the lightweight `dart:developer` helper pattern from `neiry_kit/lib/src/util/nlog.dart` (keep one example-local helper; do not depend on `mind_mobile`).

## Tasks

### Phase 1: Foundation — permissions, deps, enumeration

- [x] **Task 1: Add camera permissions to the example app**
  Files: `example/ios/Runner/Info.plist`, `example/android/app/src/main/AndroidManifest.xml`
  Add `NSCameraUsageDescription` (string explaining the rear-camera PPG measurement) to the iOS `Info.plist`. Add `<uses-permission android:name="android.permission.CAMERA" />` and an **optional** `<uses-feature android:name="android.hardware.camera.flash" />` (do **not** set `required="true"` — that would hide the app on flash-less devices) to the Android manifest. This is the minimum to let the `camera` plugin trigger the OS permission prompt and run the panel on-device. (Note: `camera_android_camerax` already merges a CAMERA permission, so the Android entry is belt-and-suspenders.) Full permission_handler denied/permanently-denied flow is out of scope (deferred to Phase 9).

- [x] **Task 2: Declare `camera` + `flutter_ppg` as direct example deps** (depends on Task 1)
  Files: `example/pubspec.yaml` (via tooling)
  `example/lib/auto_detect/` imports `package:camera/camera.dart` and `package:flutter_ppg/flutter_ppg.dart` directly, but the example currently only declares `camera_ppg_kit` (path) + `cupertino_icons` — both are merely transitive. Without explicit declaration, `flutter analyze` (flutter_lints ^6) raises `depend_on_referenced_packages`. Add them with tooling, never by hand-editing pubspec:
  ```
  cd example && /usr/local/bin/flutter pub add camera flutter_ppg
  ```

- [x] **Task 3: Rear-camera enumeration probe** (depends on Task 2)
  Files: `example/lib/auto_detect/camera_probe.dart`
  ~15-line probe: call `availableCameras()`, keep only `lensDirection == CameraLensDirection.back`, and map each to a small descriptor type (`RearCamera { int index; CameraDescription description; String name; int sensorOrientation; CameraLensType lensType; }`) in **probe order = default/main-wide first** (the order `availableCameras()` returns; do not reorder). Expose `Future<List<RearCamera>> enumerateRearCameras()`. This confirms the per-device rear-camera count for the support matrix (note 03): iOS lists every rear lens, Android one logical back. Capture `lensType` into the descriptor — it's free signal for note 03. Add a comment: *"`CameraDescription.lensType` exists but is frequently `unknown` (esp. the Android logical back), so we cannot reliably rank lenses by type; probe in `availableCameras()` order."*

### Phase 2: Coverage round-trip

- [x] **Task 4: Coverage detector + result/error types** (depends on Task 3)
  Files: `example/lib/auto_detect/auto_detect_result.dart`, `example/lib/auto_detect/coverage_detector.dart`, `example/lib/auto_detect/log.dart`
  In `auto_detect_result.dart`: a result type `CoverageOutcome` holding either the locked `RearCamera` (success) or a typed `AutoDetectError` enum (`noCoveredCamera`, `cameraError`, `permissionDenied`), plus per-camera probe progress records (camera index, frames seen, covered-frame fraction, final verdict) so the UI can show what each step found.
  In `log.dart`: copy the minimal `nlog`-style `dart:developer` helper (tag `camera_ppg_example`).
  In `coverage_detector.dart`: implement the sequential round-trip `Future<CoverageOutcome> detectCoveredCamera(List<RearCamera> cameras, {Duration warmUp = const Duration(milliseconds: 400), Duration dwell = const Duration(milliseconds: 700)})`:
  1. Hold one shared `const PPGConfig()` and the inlined coverage test `bool covered(double raw) => raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax;` (no `SignalQualityAssessor` import — see API facts).
  2. For each `RearCamera` in order: create `CameraController(..., ResolutionPreset.low, enableAudio: false, imageFormatGroup: ...)`, `initialize()`, `setFlashMode(FlashMode.torch)`.
  3. Bridge `startImageStream(callback)` → a single-listener `StreamController<CameraImage>`; the callback must check `controller.isClosed` before `add` (frames can fire briefly after teardown begins). Feed the stream to a fresh `FlutterPPGService().processImageStream(...)` and listen for `PPGSignal`s.
  4. Skip the warm-up window (let exposure/torch settle), then over the dwell window count frames where `covered(signal.rawIntensity)` is true. At `ResolutionPreset.low` (~30 fps) the 700 ms dwell yields ~21 frames. **Covered** if covered-fraction ≥ 0.6.
  5. Always tear down before moving on, in order: stop the image stream / drop the callback, cancel the signal subscription, `service.dispose()`, close the `StreamController`, `controller.setFlashMode(FlashMode.off)`, `controller.dispose()`. Never hold two controllers open at once.
  6. Lock and return the **first** covered camera. If the full pass finds none, return `AutoDetectError.noCoveredCamera`. Wrap `CameraException`/init failures into `AutoDetectError.cameraError` (or `.permissionDenied` when the exception indicates denied access) — never throw out of this function. Emit one `nlog` line per camera with its verdict.

### Phase 3: Panel UI + wiring

- [x] **Task 5: Auto-detect panel screen** (depends on Task 4)
  Files: `example/lib/auto_detect/auto_detect_screen.dart`
  A `StatefulWidget` panel that drives the spike:
  - Guidance text teaching the interaction order: "Place a finger over a rear lens **and** the flash, then press Start."
  - On first build (or a "Probe cameras" affordance), run `enumerateRearCameras()` and show the enumerated list (count + name + sensor orientation + lensType) — this is the per-device rear-camera-count readout for the matrix.
  - A **Start** button that calls `detectCoveredCamera(...)`, disabling itself while running and showing per-camera progress (which sensor is being probed, covered-frame fraction).
  - On success: show the locked camera (index + name) prominently. On failure: show the typed error message (e.g. "No covered camera — place your finger over the lens and flash") and a **Retry** that re-runs the round-trip. Returns cleanly to idle either way.
  - Keep rebuilds coarse (update on phase changes / per-camera summaries, not per frame) to avoid starving the frame stream.

- [x] **Task 6: Wire the panel as the example app home** (depends on Task 5)
  Files: `example/lib/main.dart`
  Replace the current platform-version demo home with `AutoDetectScreen` as the app's home. Strip the unused `getPlatformVersion` demo state. Keep `WidgetsFlutterBinding.ensureInitialized()` before `runApp` (required before `availableCameras()`).

## Commit Plan
- **Commit 1** (after tasks 1-4): "Add example camera permissions, deps, rear-camera enumeration probe, and signal-based coverage round-trip"
- **Commit 2** (after tasks 5-6): "Add auto-detect panel and wire it as the example app home"
