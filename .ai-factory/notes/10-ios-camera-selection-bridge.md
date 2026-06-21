# iOS — Torch Fallback (deletion candidate)

**Date:** 2026-06-21
**Source:** ROADMAP Phase 7; `camera_avfoundation` 0.10.1 (`CameraPlugin.swift` `getAvailableCameras`); `neiry_kit/ios/Classes/NeiryKitPlugin.swift` (registration pattern only); notes 01 (auto-detect), 03 (capability from sources), 06 (error values)

## Key Findings

- **Deletion candidate (note 03).** `camera_avfoundation` already exposes **every** rear lens via `availableCameras()` (wide/tele/ultrawide as separate `CameraDescription` + `lensType`), so camera **enumeration needs no native code** on iOS. The round-trip (note 01) runs in pure Dart. There is **no native selection or enumeration role** here.
- Torch runs through the `camera` plugin's `setFlashMode(FlashMode.torch)` on the active controller. This bridge ships **only** if the Phase-2 spike finds that path can't hold the torch during capture on some device — a thin **torch-only** fallback. Default expectation: the bridge is **not built** and `ios/` carries no kit-specific classes.
- What would port from neiry if it ships: only the `FlutterPlugin.register` + `do/catch → result(FlutterError)` "never crash, return a code" discipline. No C SDK, no event channel.

## Details (only if the torch fallback proves necessary)

- `CameraPpgKitPlugin.swift` — `FlutterPlugin` registering ONE method channel `camera_ppg_kit/camera` (note 04) with a single method.
- **`setTorch`** (args `{ on: Bool, level: Double? }`) — on the active rear `AVCaptureDevice`: `lockForConfiguration()`, set `torchMode` (or `setTorchModeOn(level:)`), `unlockForConfiguration()`, `result(nil)`. Errors returned as `CameraPpgError` values (note 06: `torchUnavailable` when `hasTorch == false` or `lockForConfiguration` throws), never thrown. Torch off on stop/dispose (Phase 11).

## Guards

- **Add no native enumeration or selection** — both live in Dart (notes 01/08); the iOS plugin already lists every rear lens.
- Build nothing here unless the spike proves `setFlashMode(torch)` insufficient; otherwise `ios/` stays kit-class-free.
- Single method channel, torch only; no event channel.
