# Device-Support Matrix + Go/No-Go

**Date:** 2026-06-21
**Source:** conversation context; outputs of notes 01 + 02

## Key Findings

- The whole kit is conditional on a hardware reality that varies per phone: can a fingertip cover both lens and flash, and does the frame path sustain enough FPS for a stable signal? This task converts runs of the example app's auto-detect panel (note 01) and raw stream-inspector panel (note 02) into a **decision**.
- The deliverable is an analysis document, not code — but it is atomic and gates Phases 6–11. A "no-go on most devices" outcome changes the kit from a primary source to a narrow opt-in, and that must be decided before bridges are built.
- Output also seeds the **allow/deny-list** the hardening phase (Phase 11) enforces and validates the signal-based auto-detect (note 08) the session implements.
- **The camera-exposure capability is already answered from the plugin sources — not hardware.** `camera_avfoundation` 0.10.1 returns **every** rear lens as a separate `CameraDescription` (wide / telephoto / ultrawide, with `lensType`), so the round-trip runs in pure Dart on iOS. `camera_android_camerax` 0.7.2 returns **one logical back camera** (physical sub-lenses are not reachable past CameraX), so on Android the round-trip degrades to the default back camera only. The spike therefore confirms only the per-device *count*, with a ~15-line throwaway probe before any kit code — it does not need to discover the capability.

## Details

### Deliverable

A matrix (markdown table in `.ai-factory/` or `docs/`) with one row per tested phone and columns:

- Model / camera-island layout
- Default rear camera = torch-co-located (one finger covers its lens + the torch)? (Y / hard / N)
- Rear `CameraDescription` count from `availableCameras()` (expected: iOS ≈ all physical lenses with `lensType`; Android ≈ 1 logical back) — confirms the source-derived capability per device
- Auto-detect resolves a covered sensor without manual override? (default-only / needed fallback probe / failed)
- Worst-case auto-detect time, s (finger on the last-probed sensor)
- Finger-presence reliably distinguishes covered / over-bright / uncovered? (Y / flickery / N)
- Sustained FPS (from note 02)
- RR stability vs reference (good / noisy / none)
- Verdict: **supported / marginal / unsupported**

### Go/no-go statement

**Item #1 — confirm the rear-camera count; Phase 7 is a deletion candidate.** The plugin sources already answer the *capability* (Key Findings): iOS exposes every rear lens, Android exposes one logical back camera. Native enumeration is therefore unnecessary on both platforms — **Phase 7 (notes 10/11) is a deletion candidate**, reduced at most to a thin torch fallback. The spike only confirms the per-device *count* with a ~15-line throwaway probe on real devices (simulator/emulator have no cameras):

```dart
import 'package:camera/camera.dart';
final cams = await availableCameras();
for (final c in cams) {
  print('${c.name} | ${c.lensDirection} | orient=${c.sensorOrientation}');
}
final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).length;
print('BACK cameras: $back'); // iOS Pro → 2-3; Android → expect 1
```

iOS rows can be **pre-filled from public model specs** (model → rear-lens count) and merely confirmed; Android rows are structurally one back camera, confirmed on 2–3 phones.

Then the headline conclusion: ship camera PPG as (a) a broadly-available source, (b) a marginal opt-in gated to an allow-list, or (c) shelve it. Include the allow/deny-list derived from the matrix.

### Test set

Cover the camera-island archetypes, not just brands: single-camera budget phones, dual-camera mid-range, and large-island flagships (iPhone Pro, Samsung S-Ultra, Pixel Pro) where flash–lens separation is worst.

### Verify

The document names every phone tested, the FPS and SQI numbers behind each verdict, and a one-line go/no-go that the next phases can act on without re-running hardware.

### Guards

- No silent caps: if only a few phones were tested, state that the matrix is provisional.
- Decision belongs to the user — this note produces the evidence and a recommendation, not a unilateral shelving.
