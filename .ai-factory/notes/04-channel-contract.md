# Dart Channel Contract

**Date:** 2026-06-21
**Source:** conversation context; `neiry_kit/lib/src/channel/` as the pattern; `flutter_ppg` API

## Key Findings

- Unlike neiry (8 method + 22 event channels for a C SDK), this kit may need **no method channel at all**: enumeration is Dart-side (`availableCameras()` — note 03) and torch runs through the `camera` plugin's `setFlashMode(FlashMode.torch)`. A `camera_ppg_kit/camera` channel ships **only** if the Phase-2 spike finds plugin torch insufficient (a `setTorch` fallback — notes 10/11, themselves deletion candidates). Frames, RR, SQI, and selection all flow through `flutter_ppg`/`camera` in Dart.
- The durable deliverable of this task is therefore the **enums** (used Dart-side regardless); the method-channel names are a contingency. Establishing them with uniqueness tests is cheap and lets a torch fallback be written against a frozen surface if it ever ships.
- Enums are the cross-boundary vocabulary: `MeasurementState`, `SignalQuality`, `CameraFacing`. They carry int mappings so native can emit ints and Dart decodes deterministically.

## Details

### Files

- `lib/src/channel/channel_names.dart`
- `lib/src/channel/enums.dart`
- `test/channel_names_test.dart`

Export both from `lib/camera_ppg_kit.dart`.

### Method channel — `CameraPpgChannels`

At most one method channel, e.g. `camera_ppg_kit/camera`, and only if the torch fallback ships (notes 10/11). Its single method would be `setTorch` — enumeration/selection are Dart-side (note 01/08), so `listRearCameras`/`selectCamera` are **not** needed. Keep the name as a `static const` string in a `CameraPpgMethods` holder; the holder may stay unused.

### Event channels — `CameraPpgEvents`

Minimal — most data is Dart-side via `flutter_ppg`. Reserve IDs only for things that must originate natively (e.g. torch/camera availability changes). If none are needed after Phase 6, this stays empty rather than inventing channels.

### Enums — `enums.dart`

- `MeasurementState { idle, warmup, measuring, done, poorSignal }` (+ int codes)
- `SignalQuality { good, fair, poor }` (+ int codes) — `fromSnr` lives on the model (note 05), not here
- `CameraFacing { back }` for now; lens-type metadata travels as a map, not an enum, to stay open

### Verify

`test/channel_names_test.dart`: assert every channel/method string is unique; assert each enum's int codes are unique and round-trip via `fromCode`/`code`. No native or bridge code in this task.

### Guards

- Do not add channels speculatively for data `flutter_ppg` already provides in Dart.
- Match neiry's holder-class style (`CameraPpgChannels`, `CameraPpgMethods`) for cross-kit familiarity.
