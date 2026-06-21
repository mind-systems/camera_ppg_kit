# CameraPpgSession + Streams

**Date:** 2026-06-21
**Source:** `flutter_ppg` 0.2.4 API; `camera` plugin; ARCHITECTURE.md boundary rules

## Key Findings

- This is the public surface the host calls — the analogue of neiry's `Device`. It owns a `camera` `CameraController` + a `flutter_ppg` `FlutterPPGService` and exposes only kit models over broadcast streams. `CameraImage` / `PPGSignal` / `CameraController` types must **not** leak through the barrel (ARCHITECTURE anti-pattern).
- `flutter_ppg`'s `processImageStream(Stream<CameraImage>)` does the DSP; the session's job is wiring (camera config + torch + frame stream in, kit models out) and lifecycle (start/stop, dispose, release).
- Conversion happens at this edge: `PPGSignal.rrIntervals → RrInterval`, `PPGSignal.sqi/snr → SignalQuality`, presence/state → `MeasurementState`. The Phase 8 acceptance gate and Phase 6 session policy plug in here later; this task is the bare wired session.
- **Do not discard the red-channel on conversion.** The example's `[debug]` waveform (note 14) needs it: the session taps the *same* `PPGSignal` it already receives and emits the raw/filtered red-channel as a `[debug]`-tagged `debugSignalStream` of `List<double>`. It crosses as `List<double>` only — never `PPGSignal`/`CameraImage` — so the barrel boundary holds; it is **absent from the consumer freeze** (note 19).

## Details

### `lib/src/api/camera_ppg_session.dart`

Public API:
- `Future<void> start()` — run the signal-based auto-detect round-trip on Start (note 01/08: open each rear sensor in probe-order with torch + a short coverage dwell, lock the first covered; or honour a pinned `useCamera`). On a lock, keep that `CameraController` (`ResolutionPreset.low`, audio off) streaming via `startImageStream` → `FlutterPPGService.processImageStream`. On no covered sensor, surface a typed `CameraPpgError` (note 06) and return to idle.
- `Future<void> stop()` / `Future<void> dispose()` — stop the stream, release the controller + torch.
- `Stream<RrInterval> get rrStream` (broadcast)
- `Stream<SignalQuality> get qualityStream` (broadcast)
- `Stream<MeasurementState> get stateStream` (broadcast)

**Debug-only surface** (note 14/19 — not part of the consumer contract, both tagged `[debug]`):
- Optional ctor input `RrAcceptanceConfig? acceptance` (default `null` → `RrAcceptance`'s internal defaults, note 12). The single debug-tagged optional **input**; the host leaves it unset. Lets the playground reconstruct the session with custom gate thresholds for spike tuning.
- `Stream<List<double>> get debugSignalStream` (broadcast) — the raw/filtered red-channel tapped off `PPGSignal`. A debug-tagged **output**; `List<double>` only.

Internally: one `FlutterPPGService`, a subscription that maps each `PPGSignal` to kit models and fans out to the three `StreamController`s. Keep the controllers open across measurements (re-`start()` without recreating the session), seeding empty until the first signal — same "streams stay open, fed on start" pattern as neiry's `NeiryService`.

### Export

`export 'src/api/camera_ppg_session.dart';` from `lib/camera_ppg_kit.dart`.

### Verify

A widget/integration test (or the example) can `start()`, receive `RrInterval`s and `SignalQuality` events with a finger on the lens, and `stop()`/`dispose()` releases the camera (torch off, controller disposed) with no late events.

### Guards

- No `flutter_ppg`/`camera` type in any public signature — convert at the boundary. The debug surface obeys this too: `RrAcceptanceConfig` is a plain kit value, `debugSignalStream` is `List<double>` — neither leaks `PPGSignal`/`CameraImage`.
- The debug input/output exist for the example and tests only; they must be enumerated in note 19's freeze as the explicit `[debug]` extras so the consumer contract stays honest — never silently present.
- Do not bake acceptance/warm-up logic in yet (Phase 6/8) — keep this the minimal wired passthrough so those land as separate reverts.
- Camera selection is the session's own signal-based auto-detect (note 01/08), run inside `start()`: the session enumerates/probes rear sensors and locks on the covered one, or honours a pinned `useCamera`. The native bridge, if present, only supplies sensor IDs + torch (notes 10/11) — it makes no selection decision.
