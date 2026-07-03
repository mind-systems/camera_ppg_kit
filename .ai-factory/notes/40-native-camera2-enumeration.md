# Native camera2 rear-lens enumeration (Android)

**Date:** 2026-07-03
**Source:** conversation context (reach physical lenses the Flutter plugin hides)

## Goal

Expose **every** physical rear lens the Flutter `camera` plugin hides. On Android the
plugin's `availableCameras()` returns one logical back camera (CameraX
`getAvailableCameraInfos()` collapses the module and skips `LENS_FACING.unknown`
sub-cameras), so the ultrawide that sits closest to the flash — the ideal contact-PPG
lens — is unreachable. This task adds the native enumeration; capture is note 41.

This is the first step that **reintroduces native Android code**, which the kit had
dropped (note 03). Android-only: iOS already exposes each lens via `availableCameras()`.

## Current state

`android/src/main/kotlin/com/mind/camera_ppg_kit/CameraPpgKitPlugin.kt` is a bare plugin
scaffold (platform-version stub). No camera2 access. Dart-side enumeration is
`cam.availableCameras()` only.

## The change

- Native (Kotlin): a method-channel handler using `CameraManager.getCameraIdList()` (and
  `CameraCharacteristics.getPhysicalCameraIds()` on logical multi-cameras where present)
  to list all **rear** camera2 ids with descriptive metadata — id, `LENS_FACING`,
  focal-length / `REQUEST_AVAILABLE_CAPABILITIES` hints so an ultrawide vs main can be
  told apart where the OS provides it.
- Dart: a `NativeCameraCatalog` (`lib/src/capture/native_camera_catalog.dart`) calling
  that channel and mapping results to the existing `CameraPpgCameraInfo` model — never
  leaking a raw camera2 handle. Never throws across the boundary (empty list on failure),
  matching `availableCameras()`.

## Guards

- Enumeration only — no capture, no torch, no session opened in this task.
- Android-only; on iOS this catalog is absent/empty and the plugin path is used.
- Map to `CameraPpgCameraInfo` at the edge; no native/camera2 type crosses the boundary.
- Reversible independently of notes 39/41 — it adds a catalog, it does not rewire capture.

## Verify

- On the A70: the native catalog lists more rear lenses than `availableCameras()`'s
  single "0 (unknown)" — in particular the ultrawide that the stock camera app's "wide"
  mode uses. Record the ids/metadata seen in note 03.
