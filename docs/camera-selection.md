# Camera selection and coverage

The central hardware problem of contact PPG is that a single fingertip must cover **a lens and the torch at once**, which is only possible where they sit close together. The kit resolves which lens to use from the signal, and offers manual override and a live preview so coverage can be confirmed.

## Auto-detect round-trip

On `start()` with no override, the kit runs one sequential round-trip over the rear sensors: for each, it opens the camera, turns the torch on, and measures the covered-frame fraction over a short dwell. The first sensor whose coverage passes is locked; if none is covered, `start()` returns `CameraPpgError.noFinger`. The round-trip is sequential because the rear camera and torch cannot be opened concurrently.

Coverage is read from `flutter_ppg`'s red-channel intensity via `FingerPresence`: an in-band intensity is `present`, too dark is `absent`, blown-out is `overBright`. Intensity alone is a coarse proxy — it confirms the lens sees a lit fingertip, not that the finger is optimally placed.

## Enumeration differs by platform

`availableCameras()` returns a `CameraPpgCameraInfo` list of the rear lenses:

- **iOS** exposes every rear lens (wide / ultrawide / telephoto) as a separate entry.
- **Android** exposes one logical back camera; the physical sub-lenses behind it are not surfaced through the `camera` plugin, so the list has a single rear entry.

## Override and verification

- `useCamera(id)` pins a specific lens from `availableCameras()` and skips the auto-detect round-trip on the next `start()`.
- `resolvedCamera` (and its stream) reports which lens is actually active, so a UI can label it.
- `buildPreview()` returns the live view of that lens. Because auto-detecting which physical lens the finger covers is coarse, the preview is how a user confirms the finger is on the right lens and getting a clean, fully-red frame — poor coverage shows as a dim or non-uniform frame rather than a saturated red field.
