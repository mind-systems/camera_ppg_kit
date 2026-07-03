# Measurement session

A measurement is driven through `CameraPpgSession` (`package:camera_ppg_kit/camera_ppg_kit.dart`). The session owns the camera, the torch, and the signal pipeline, and fans out the results as broadcast streams. Higher-level numbers (BPM, HRV) are not produced here — the consumer derives them from the RR stream.

## Lifecycle

`start()` runs the camera round-trip and begins streaming; `stop()` releases the camera and torch; `dispose()` releases and closes the streams for good. The broadcast streams open once and stay open across repeated `start()`/`stop()` cycles, so a consumer subscribes once and keeps listening.

`MeasurementState` moves through:

```
idle → warmup → measuring ⇄ poorSignal
```

- **idle** — not running.
- **warmup** — a sensor is locked; RR is not yet trusted while the signal settles.
- **measuring** — RR is trusted and flowing.
- **poorSignal** — the finger left the lens or quality dropped below the floor; RR stops flowing until it recovers. The session never self-completes; it returns to `idle` only on `stop()`/`dispose()`.

## Streams

| Stream | Carries |
|---|---|
| `rrStream` | `RrInterval { intervalMs, timestamp, isArtifact }` — one per accepted beat, artifacts flagged, never silently dropped |
| `qualityStream` | `SignalQuality` — `good` / `fair` / `poor`, derived from SNR |
| `stateStream` | `MeasurementState` transitions |
| `fingerPresenceStream` | `FingerPresence` — `present` / `absent` / `overBright` |
| `resolvedCameraStream` | `CameraPpgCameraInfo?` — which lens is active, or `null` when none |

`buildPreview()` returns a live camera-texture `Widget?` for the active lens (or `null` when nothing is streaming), so a UI can show what the camera sees.

## RR intervals

`RrInterval.intervalMs` is the beat-to-beat time in milliseconds. `isArtifact` marks a beat the acceptance gate rejected (out of physiological range or inconsistent with the recent rhythm) — the beat is still emitted so a consumer can see it, but it is excluded from any rate/HRV derivation. `timestamp` is the time of the later of the two peaks bounding the interval.

## Errors

`start()` returns a typed `CameraPpgError` instead of throwing — `permissionDenied`, `noFinger` (no covered sensor), `torchUnavailable`, `cameraUnavailable`, `unsupportedDevice`. A `null` return means success. `poorSignal` and no-finger are ordinary states, not errors: the stream simply stops emitting until the signal returns.
