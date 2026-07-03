# NativeCamera2FrameSource — native capture feeding flutter_ppg

**Date:** 2026-07-03
**Source:** conversation context (dual frame-source: the native capture backend)

## Goal

A second `FrameSource` (note 39) backed by native Android camera2 that opens a chosen
physical rear lens (note 40) — including the near-flash ultrawide — and feeds its frames
into the **same** DSP pipeline the plugin path uses. `flutter_ppg` stays the DSP; only
the frame origin changes. Both backends coexist; this adds the native one.

## Current state

Notes 39/40 exist: the `FrameSource` interface with `CameraPluginFrameSource`, and the
native rear-lens catalog. The frame isolate already reconstructs a `CameraImage` from a
`FrameMessage` via `cameraImageFromFrameMessage` (`frame_isolate.dart:74`,
`CameraImage.fromPlatformData`) and runs `flutter_ppg` on it — so any backend that
produces a well-formed `FrameMessage` (YUV planes + strides + format) feeds the DSP
unchanged. No native capture exists yet.

## The change

- Native (Kotlin): open the chosen camera2 id, configure an `ImageReader`
  (`YUV_420_888`) capture session, enable torch (capture-request `FLASH_MODE_TORCH`),
  and best-effort AE/AF lock (mirroring the plugin path's stability locks). Deliver each
  frame's YUV plane bytes + width/height/row-&-pixel strides + format over an
  `EventChannel` (or a lower-overhead binary transport if the event channel proves too
  slow at ~30 fps). Ordered teardown: stop repeating request → close session → torch
  off → close `ImageReader` → close device.
- Dart: `NativeCamera2FrameSource` (`lib/src/capture/native_camera2_frame_source.dart`)
  implementing `FrameSource` — builds a `FrameMessage` **directly** from each channel
  frame (no `CameraImage` on the producer side) and exposes it as `frames`, so
  `CameraPpgSession` drives the existing `FrameIsolate` from it exactly as it does the
  plugin source. Opens a default rear lens (the ultrawide where identifiable, else id 0);
  arbitrary selection is note 42.

## Guards

- `flutter_ppg` and the isolate/de-halving/gate pipeline are untouched — the frame just
  arrives as a `FrameMessage` from a different producer.
- Frame delivery must not starve FPS (note 13 / CLAUDE.md); if the event-channel path is
  too slow, report it and switch transport — do not silently drop frames.
- Ordered native teardown must leave the torch **off** and the device closed on every
  path (the A70 torch-stuck deadlock class, note 02).
- Android-only. iOS keeps the plugin source.
- Reintroduces native capture — the core of the "dual source" reversal of note 03.

## Verify

- On the A70: selecting the native source runs a full measurement off the ultrawide lens
  (finger over the near-flash lens), producing plausible RR/SQI through the unchanged DSP;
  Stop leaves the torch off. The plugin source still works unchanged.
