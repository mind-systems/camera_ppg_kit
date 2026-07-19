# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`camera_ppg_kit` is a **Flutter plugin** that turns the phone's rear camera + flash (torch) into a contact-PPG heart-rate source: a fingertip over the lens and LED, and the kit emits a stream of **RR intervals** (ms) plus a signal-quality assessment. BPM/HRV are left to the consumer.

It wraps two packages — [`flutter_ppg`](https://pub.dev/packages/flutter_ppg) (the signal DSP) and [`camera`](https://pub.dev/packages/camera) (frame stream + torch) — and adds the parts they leave to the host. An `example/` app exercises the source end-to-end on real hardware.

## flutter_ppg vs what the kit adds

`flutter_ppg` owns the DSP: red-channel extraction, bandpass, peak detection, RR intervals, SNR/SQI, finger-presence. Its only camera coupling is `extractRedChannel(CameraImage)` — one number per frame; everything downstream runs on the 1-D intensity series.

The kit adds what `flutter_ppg` leaves to the host:

| Concern | Where |
|---|---|
| Camera selection (signal-based auto-detect) + override | `src/api/camera_ppg_session.dart` |
| Torch, warm-up, session lifecycle | `src/api/camera_ppg_session.dart`, `src/processing/session_policy.dart` |
| Off-UI-isolate frame path | `src/processing/frame_isolate.dart`, `frame_message.dart` |
| De-halving (harmonic-pair merge) | `src/processing/rr_dehalving.dart` |
| Physiological acceptance gate | `src/processing/rr_acceptance.dart` |

## Structure

| Path | Purpose |
|---|---|
| `lib/camera_ppg_kit.dart` | Public barrel — the only import a consumer uses |
| `src/api/camera_ppg_session.dart` | Measurement surface: start/stop/dispose, the streams, `availableCameras()`/`useCamera()`, `buildPreview()`, `resolvedCamera` |
| `src/models/` | Value types that cross the barrel: `RrInterval`, `SignalQuality`, `MeasurementState`, `FingerPresence`, `CameraPpgError`, `CameraPpgCameraInfo` |
| `src/processing/` | Dart signal handling on top of flutter_ppg — de-halving, acceptance gate, session policy, frame isolate |
| `example/` | Standalone app to exercise the source on real hardware |

## Invariants (do not break)

- **No wrapped type crosses the barrel.** `PPGSignal` / `CameraImage` / `CameraController` never appear in a public signature — the API layer converts to `src/models/` types at the edge.
- **Frame path:** camera → `FrameMessage` → `FrameIsolate` (off the UI isolate) → flutter_ppg → **de-halving → acceptance gate** → streams. De-halving runs *before* the gate.
- **Teardown:** close the input `StreamController<CameraImage>` **before** cancelling the `PPGSignal` subscription — flutter_ppg's `async*` `processImageStream` deadlocks otherwise. Release is ordered and idempotent (`_release()`).
- **One camera at a time.** The rear camera + torch cannot be opened concurrently; the auto-detect round-trip is sequential — the finger picks the lens, the kit locks the first covered sensor.
- **RR + quality only.** The kit never emits BPM/HRV — the consumer derives them.
- **FPS-sensitive.** Heavy UI work starves the frame stream; keep the frame path off the UI isolate and measure on a quiet screen.

## Commands

```bash
flutter run                 # example on a connected real device (no camera/torch on simulators)
flutter test
flutter analyze
flutter pub add <package>   # never hand-edit pubspec.yaml
```

## Documentation

| Doc | What it covers |
|---|---|
| [README.md](README.md) | Overview, requirements, installation, running the example |
| [docs/measurement.md](docs/measurement.md) | Session lifecycle, streams, RR intervals, errors |
| [docs/camera-selection.md](docs/camera-selection.md) | Auto-detect round-trip, override, coverage, preview |
| [docs/signal-processing.md](docs/signal-processing.md) | De-halving, acceptance gate, session policy |
| [docs/device-support.md](docs/device-support.md) | Per-device hardware notes, tested devices, calibration |
| [.ai-factory/ARCHITECTURE.md](.ai-factory/ARCHITECTURE.md) | Module structure, layers, dependency rules |
