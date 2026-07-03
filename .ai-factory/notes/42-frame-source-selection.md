# Unified camera selection + live preview — public coverage-UX contract (cross-platform)

**Date:** 2026-07-03
**Source:** conversation context (both backends behind one list; iOS/Android parity; expose to integrator)

## Goal

Make **choosing the capture lens and verifying coverage** a first-class, **cross-platform
identical** part of the **consumer** contract — not a dev-only affordance. Auto-detecting
which physical lens the finger actually covers is unsolved (the "covered" signal doesn't
discriminate — the torch tints every lens pink), so the near-term model is: the
integrator's end-user **picks** the lens and **confirms** coverage on the **live
preview**. The two capture backends (notes 39/41) are unified behind one camera list; the
plugin-vs-native distinction never appears in the public API.

## Current state

Notes 39–41 give the `FrameSource` seam, `CameraPluginFrameSource` (default),
`NativeCamera2FrameSource`, and the native rear-lens catalog (note 40). `buildPreview()`
(note 35) and `resolvedCamera` (note 36) already exist and are barrel-exported. But
`availableCameras()` still returns only plugin lenses, `useCamera(id)` only plugin ids,
and the selection/preview are positioned as example verification, not consumer contract.

## The change

- **Unified list (kit).** `availableCameras()` returns ONE `CameraPpgCameraInfo` list
  merging the plugin lens(es) and — on Android — the native camera2 lenses (note 40).
  Each entry's id encodes its backend so `useCamera(id)` routes internally to
  `CameraPluginFrameSource` or `NativeCamera2FrameSource`. The caller sees one list, one
  `useCamera` — "plugin vs native" is never a public concept.
- **Cross-platform identical.** iOS list = all rear lenses the plugin already exposes;
  Android list = the plugin logical back + the native physical lenses (incl. the
  near-flash ultrawide). Same public shape, same behavior, same UX on both — this parity
  is a **requirement**, not a nicety (the end-user experience must be identical).
- **Coverage-UX is contract, not debug.** `availableCameras()`/`useCamera(id)` +
  `buildPreview()` (note 35) + `resolvedCamera`/its stream (note 36) together are the
  supported, frozen way (note 19) for the integrator to let its end-user pick a lens and
  verify coverage on the live video. `mind_mobile` is expected to surface these to its
  own measurement UI.
- **Example.** `_cameraOverrideCard` shows the unified dropdown + preview (note 38) +
  resolved-lens label — identical on iOS and Android. An optional **debug-only** "force
  backend (plugin/native)" control may remain for on-device A/B, clearly secondary to the
  unified list.

## Guards

- No user-visible "backend" concept in the public API — one list, backend hidden behind
  the id.
- iOS and Android must expose the identical public shape and UX — parity required.
- Selection applies on the next `start()`; gate on lifecycle (note 33), no
  mid-measurement switch (one camera open at a time, note 01).
- Auto-detecting the covered lens is **out of scope here** and unsolved; until it exists,
  selection is user-driven + preview-verified. A future auto-detect item may layer a
  smart default on top without changing this surface.

## Verify

- One code path on both platforms: `availableCameras()` returns a multi-lens list,
  `useCamera(id)` picks one, `buildPreview()` shows it, `resolvedCamera` reports it; the
  end-user confirms the finger is on the chosen lens. Android's list includes the native
  ultrawide; iOS's includes every rear lens. No backend concept surfaces anywhere.

Depends on notes 39/40/41 (and the already-shipped 35/36).
