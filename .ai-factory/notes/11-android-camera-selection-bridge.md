# Android — Torch Fallback (deletion candidate)

**Date:** 2026-06-21
**Source:** ROADMAP Phase 7; `camera_android_camerax` 0.7.2 (`CameraSelector.defaultBackCamera`, `getAvailableCameraInfos`); `neiry_kit/android/.../NeiryKitPlugin.kt` (MethodChannel pattern); notes 01 (auto-detect), 03 (capability from sources), 10 (iOS sibling)

## Key Findings

- **Deletion candidate (note 03).** `camera_android_camerax` exposes **one logical back camera** and does not surface physical sub-lenses; reaching them via raw Camera2 past CameraX is painful and pointless — the default back camera is the main wide at the torch, the correct sensor anyway. So there is **no native enumeration role**; the Android round-trip (note 01) is simply the default back camera.
- Torch runs through the `camera` plugin's `setFlashMode(FlashMode.torch)` on the active capture session — the correct path, because native `CameraManager.setTorchMode` throws `CameraAccessException` (CAMERA_IN_USE) while the plugin owns the device. This bridge ships **only** if the spike finds `setFlashMode(torch)` insufficient on some device — a thin **torch-only** fallback. Default expectation: **not built**; `android/` carries no kit-specific Kotlin.
- Ports from neiry only if it ships: the plugin/handler shape (`onAttachedToEngine` registers `MethodChannel`, `when (call.method)` dispatch, `result.error` discipline). No `NativeBridge`/JNI — no vendored SDK.

## Details (only if the torch fallback proves necessary)

- `CameraPpgKitPlugin.kt` — `FlutterPlugin, MethodCallHandler`; registers one `MethodChannel("camera_ppg_kit/camera")` with a single `setTorch { id, on }` delegating to `CameraManager.setTorchMode`; catch `CameraAccessException` → typed `CameraPpgError` (note 06: `torchUnavailable`/`cameraInUse`), never thrown across the channel.

## Guards

- **Add no native enumeration or selection** — both live in Dart (notes 01/08); CameraX gives one logical back camera and that is the right sensor.
- Build nothing unless the spike proves `setFlashMode(torch)` insufficient; otherwise `android/` stays kit-class-free.
- Error codes byte-match iOS; real device only (emulators have no torch).
