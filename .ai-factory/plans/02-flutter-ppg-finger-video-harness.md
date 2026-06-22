# Plan: flutter_ppg finger-video harness

## Context
Add the raw stream-inspector panel to the `example/` app: take the camera locked by the Phase-2 auto-detect probe, run a continuous `CameraImage` → `FlutterPPGService.processImageStream` feed, and render the live raw `PPGSignal` output (RR/derived BPM, SQI, SNR, finger-presence, sustained + detected FPS) with no acceptance policy or session lifecycle — answering, per device, "does a usable signal exist and what FPS does the frame path sustain under a static screen?".

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Constraints (from notes 01/02 + ARCHITECTURE)
- **All new code lives in the `example/` app** — this is the developer playground stage, not the kit's `lib/src/` API (those come in Phases 3–5, gated by the go/no-go). Do not add anything under `lib/src/`.
- **No acceptance policy, no session lifecycle, no isolate** — raw passthrough only. RR bounding, gating, warm-up, and isolate offload are explicitly later phases (6/8). Display `PPGSignal` fields verbatim.
- **The screen must stay visually minimal and rebuild slowly.** Heavy UI work / per-frame `setState` starves the frame stream and corrupts the very FPS number being measured (note 02 Guards). UI must throttle rebuilds independently of frame arrival.
- **Real device only** — `availableCameras()`/torch are unavailable on simulators; tolerate failures without crashing.
- Reuse the established camera-open + ordered-teardown pattern and `ppgLog` from `example/lib/auto_detect/`. No new dependencies (`camera` + `flutter_ppg` already in `example/pubspec.yaml`).

## API facts (verified against flutter_ppg 0.2.4)
- `FlutterPPGService.processImageStream(Stream<CameraImage>)` yields one `PPGSignal` per input frame.
- `PPGSignal` fields available to render: `rawIntensity`, `filteredIntensity`, `rrIntervals` (`List<double>` ms), `quality` (`SignalQuality.poor/fair/good`), `timestamp`, `snr`, `frameRate` (flutter_ppg's *detected/nominal* FPS), `isFPSStable`, `driftRate`, `sdrr`, `isSDRRAcceptable`, `rejectionRatio`, `rejectedIntervalCount`.
- There is **no `fingerPresence` field** on `PPGSignal`. Finger-presence is derived from `rawIntensity` against `PPGConfig.fingerPresenceMin/Max` — exactly the inline `covered(...)` check in `coverage_detector.dart`.
- `frameRate` is flutter_ppg's own estimate; note 02 requires the **sustained** FPS, so the harness must also measure frame-arrival rate itself (count emitted signals over a rolling wall-clock window).

## Tasks

### Phase 1: Continuous data path

- [x] **Task 1: Shared finger-presence helper**
  Files: `example/lib/common/finger_presence.dart`, `example/lib/auto_detect/coverage_detector.dart`
  Extract the coverage/finger-presence discriminator (currently inlined in `coverage_detector.dart` as `covered(double raw) => raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax`) into one reusable pure function, e.g. `bool isFingerPresent(double rawIntensity, {PPGConfig config = const PPGConfig()})`. Refactor `coverage_detector.dart` to call this helper instead of its local closure (keep behavior identical — same `PPGConfig` thresholds). Pure Dart; no Flutter/camera imports beyond `flutter_ppg`'s `PPGConfig`.

- [x] **Task 2: Sustained-FPS meter**
  Files: `example/lib/common/fps_meter.dart`
  Add a small pure-Dart `FpsMeter` that records frame arrival timestamps and reports a rolling sustained FPS over a fixed window (e.g. last ~2 s): `void record(DateTime now)` and `double get fps` (0.0 until enough samples). This is independent of `PPGSignal.frameRate` — it measures what the frame path actually delivers under the live screen. No Flutter imports so it stays trivially correct and reusable.

- [x] **Task 3: Continuous measurement runner** (depends on Task 1, Task 2)
  Files: `example/lib/inspector/measurement_runner.dart`
  Add a `MeasurementRunner` that owns a single continuous capture session on a given `RearCamera` (from `auto_detect/camera_probe.dart`):
  - `Future<void> start(RearCamera camera)` — open `CameraController` at `ResolutionPreset.low`, `enableAudio: false`, platform `imageFormatGroup` (bgra8888 iOS / yuv420 Android, as in `coverage_detector.dart`); `setFlashMode(FlashMode.torch)`; then **best-effort lock exposure/focus** via `setExposureMode(ExposureMode.locked)` / `setFocusMode(FocusMode.locked)` each wrapped in try/catch (note 02: auto-exposure chases and flattens the signal; not all platforms support locking).
  - Bridge `startImageStream` → a `StreamController<CameraImage>` (guard `isClosed`, mirror the L1 `?.` pattern from `coverage_detector.dart`) → `FlutterPPGService.processImageStream`.
  - Expose `Stream<PPGSignal> get signals` (**broadcast**) and `double get sustainedFps` (backed by the `FpsMeter`, fed one `record(...)` per emitted signal). Run continuously — no warm-up/dwell windows, no per-camera round-trip.
  - `Future<void> stop()` — reuse the ordered teardown from `coverage_detector.dart` (stop image stream → cancel subscription → dispose service → close controller → torch off → dispose controller), tolerating nulls and being safe to call twice. Route lifecycle/error logs through `ppgLog`. Surface camera-open failures without throwing into the UI build path (log + leave `signals` idle).

### Phase 2: Inspector UI + wiring

- [x] **Task 4: Stream-inspector screen** (depends on Task 1, Task 3)
  Files: `example/lib/inspector/stream_inspector_screen.dart`
  Add `StreamInspectorScreen` (plain `StatefulWidget` + `setState`; Riverpod/go_router stay deferred to Phase 9) taking the locked `RearCamera`. In `initState` create and `start()` the `MeasurementRunner`; in `dispose` `stop()` it.
  - **Throttle rebuilds, do not `setState` per frame.** Keep a `PPGSignal? _latest` updated by the `signals` listener *without* `setState`; drive the UI from a `Timer.periodic` (~300 ms / ~3 Hz) that calls `setState` reading `_latest` + `runner.sustainedFps`. Per the note, this slow, animation-free repaint is the whole point — frequent rebuilds would corrupt the FPS being measured.
  - Render the raw output (monospace, static layout, no animations): latest RR interval(s) from `rrIntervals` (ms) and **derived BPM = `60000 / lastRrMs` for display only**; current `quality` (SQI); `snr`; **finger-presence** via the Task-1 helper on `rawIntensity`; **sustained FPS** (from runner) alongside flutter_ppg's `frameRate` + `isFPSStable`; and the remaining raw diagnostic fields (`driftRate`, `sdrr`/`isSDRRAcceptable`, `rejectionRatio`/`rejectedIntervalCount`, `rawIntensity`/`filteredIntensity`).
  - Accumulate a **running SQI tally** (poor/fair/good counts + percentages over the run) incremented cheaply in the stream listener — this is the "SQI distribution over a 60 s hold" capture from note 02. Show elapsed run time so a tester can hold ~60 s.
  - A Back/Stop affordance returns to the auto-detect screen (which triggers `dispose` → teardown).

- [x] **Task 5: Wire auto-detect → inspector navigation** (depends on Task 4)
  Files: `example/lib/auto_detect/auto_detect_screen.dart`
  On a successful coverage outcome (`outcome.isSuccess`), add an "Open stream inspector" affordance in the success banner/section that `Navigator.push`es to `StreamInspectorScreen(camera: outcome.lockedCamera!)`. Keep the existing per-camera probe records and retry-on-failure UI unchanged. Ensure only one camera session is live at a time — the auto-detect round-trip fully tears down before navigation, and the inspector owns the camera for its lifetime.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add continuous PPG measurement runner and FPS meter for example harness"
- **Commit 2** (after tasks 4-5): "Add raw stream-inspector panel wired from auto-detect"
