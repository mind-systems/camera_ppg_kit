# Camera Auto-Detect (signal-based)

**Date:** 2026-06-21
**Source:** conversation context; `flutter_ppg` 0.2.4 (finger-presence); `camera` plugin API; notes 02 (raw signal/FPS), 08 (productionized selection)

## Key Findings

- **Finger placement selects the camera.** Contact PPG works only where one fingertip covers a lens **and** the torch at once, which is possible only where they sit close together — so wherever the user comfortably covers both, that sensor is torch-co-located by construction. The kit lets the finger choose, then **detects which camera got covered** (finger-presence/signal) and uses it.
- A covered lens + torch has an unmistakable signature the library we already use reads directly: red channel saturated, low spatial variance, a pulsatile component → `flutter_ppg`'s **finger-presence**. That becomes the selection signal.
- **Hard constraint: rear cameras cannot be opened all at once.** Android forbids concurrent physical-camera access on ~all devices; iOS `AVCaptureMultiCamSession` is limited to some devices and is power/thermally heavy. So detection is **sequential**, not parallel — acceptable for a deliberate "place your finger and hold still" interaction.
- **Platform asymmetry — known from the plugin sources (note 03).** `camera_avfoundation` lists **every** rear lens (wide/tele/ultrawide) as a separate `CameraDescription` with `lensType`, so the round-trip has several sensors to try on iOS. `camera_android_camerax` lists **one logical back camera**, so on Android the round-trip is just the default back camera — which is the main wide at the torch, the correct sensor in the common case anyway. Same Dart code; the list length differs by platform.

## Design — round-trip on Start

0. **Engagement = the Start button (deliberate).** Measurement is a "measure now" action, not ambient sensing. The interaction contract is **place the finger over a lens + the flash first, then press Start** — so at Start the finger is already in place and auto-detect is a one-shot, not an open-ended wait. The UI guidance must teach this order.
1. **One round-trip in probe-order.** On Start, try the rear `CameraDescription`s `availableCameras()` returns — default/main-wide first, then the rest — each with torch on and a short coverage dwell (~0.5–1 s). Lock onto the first that reads **covered**. On iOS the list has several lenses; on Android it is one back camera, so the round-trip is a single check. The common case (default = torch-co-located, finger on it) locks on the first check either way.
2. **Probe order = most-likely-covered first.** Ordering by which sensor the finger most likely covers minimises the round-trip. *This is where the old torch-proximity heuristic lives now — as probe priority, never as the selection decision.*
3. **Select on coverage, not on pulse.** Locking needs only the fast "this lens is covered" discriminator (red-dominant, high DC, low spatial variance, not over-bright) — not a confirmed pulse, which costs seconds of periodicity. The warm-up confirms the pulse *after* the lock. This keeps the round-trip to ~1–3 s even when it sweeps every sensor.
4. **Fail fast, retry.** If the full round-trip finds no covered sensor, surface a typed `CameraPpgError` (note 06: "no covered camera — place your finger over the lens and flash") and return to idle; the user repositions and presses Start again. There is no loop, so the torch flickers only during the single pass.

## What this Phase-2 panel must establish (the real spike questions)

This panel is the raw Phase-2 stage of the single example app (note 14). It answers, per target phone:

- **Per-device rear-camera count (the capability is already known from plugin sources, note 03).** iOS lists every rear lens, Android lists one logical back camera — so native enumeration is unnecessary on both platforms and **Phase 7 is a deletion candidate**. The spike only confirms the count with a ~15-line probe; it does not need to discover the capability.
- Does the `camera` plugin's **default** rear camera open the torch-co-located sensor? (almost certainly yes — it is the main wide)
- Is `flutter_ppg` **finger-presence reliable enough** to distinguish covered / over-bright / uncovered — it is now the linchpin of selection: the coverage discriminator each step of the round-trip relies on.

Outcome feeds note 03 (matrix) and note 08 (productionized auto-detect).

## Guards

- Real device only — emulators have no torch.
- **Selection is empirical** — the covered-finger signal (`flutter_ppg`'s finger-presence) decides which camera to use.
- Lock on **coverage**, not on a confirmed pulse — pulse is the warm-up's job after the lock.
- The finger is placed **before** Start, so auto-detect is one round-trip, not an open-ended wait — on no covered sensor, fail with a typed error, never loop.
- Do not open multiple cameras concurrently — probe sequentially.
- This panel proves the mechanism; the production auto-detect lives in note 08 / the session and runs on Start (no new state — success enters `warmup`, failure returns to idle with a typed error).
