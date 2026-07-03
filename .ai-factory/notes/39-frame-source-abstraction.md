# FrameSource abstraction — pluggable capture behind one interface

**Date:** 2026-07-03
**Source:** conversation context (dual frame-source: keep plugin, add native)

## Goal

Introduce a `FrameSource` seam so `CameraPpgSession` can be fed by more than one capture
backend, with the **existing `camera`-plugin path as the first implementation and
default**. No new capability and no behavior change in this task — pure enabling
refactor so the native camera2 source (notes 40–42) slots in without touching the plugin
path again. The two backends coexist; this task only carves the interface.

## Current state

`CameraPpgSession` (`lib/src/api/camera_ppg_session.dart`) directly owns a `camera`
`CameraController`: it opens it (`ResolutionPreset.low`), sets torch/exposure/focus
locks, `startImageStream`s, converts each `CameraImage` to `FrameMessage`
(`frameMessageFromCameraImage`, `frame_isolate.dart:30`), and feeds `FrameIsolate`. The
capture backend is hard-wired into the session; enumeration is `cam.availableCameras()`.

## The change

- Define an internal `FrameSource` interface (`lib/src/capture/frame_source.dart`):
  `Future<List<CameraPpgCameraInfo>> enumerate()`, `Future<void> open(cameraId)`,
  `Stream<FrameMessage> frames`, torch on/off, and an ordered idempotent `dispose()`
  honoring the close-before-cancel teardown invariant (notes 07/13).
- Extract today's plugin capture into `CameraPluginFrameSource` implementing it — the
  `CameraController` lifecycle, torch/lock setup, `startImageStream`, and the
  `CameraImage → FrameMessage` conversion all move here unchanged.
- `CameraPpgSession` holds a `FrameSource` (constructor-injectable, defaulting to
  `CameraPluginFrameSource`) instead of a `CameraController`, and drives the frame
  isolate from `source.frames`. Everything downstream (isolate, flutter_ppg,
  de-halving, gate, streams) is untouched — both backends converge on `FrameMessage`.

## Guards

- Zero behavior change: the plugin path is byte-for-byte the same capture, just relocated
  behind the interface; existing tests and on-device behavior must be identical.
- Keep the ordered teardown (close input bridge before cancelling the subscription,
  notes 07/13) inside `CameraPluginFrameSource.dispose()`.
- No barrel export of `FrameSource` yet — internal seam; the public API is unchanged.
- No native code in this task.

## Verify

- `flutter test` green; a measurement on device behaves exactly as before (same RR/SQI,
  same auto-detect, same teardown), now routed through `CameraPluginFrameSource`.
