# Live camera preview of the selected sensor

**Date:** 2026-07-03
**Source:** conversation context (verify camera selection is correct)

## Why

Peak-halving is now suspected to be self-inflicted: the native `flutter_ppg` example
fixes one camera **and shows a live preview**, so the user aligns the finger over the
correct lens and gets a clean waveform; ours auto-detects blind (no preview) and locks
the *first sensor whose red intensity passes* (`coverage_detector.dart` —
`isFingerPresent(rawIntensity)`, not signal quality). We need to see what the locked
camera actually streams to confirm the finger is on the right lens and not producing the
doubled signal. This is the verification affordance the example never got (the
implementer copied the library example's data panels but not its functional preview).

## Constraint that forces the design

The rear camera + torch cannot be opened concurrently (note 01), so the example
**cannot** open its own second `CameraController` for preview while the kit measures.
The preview must come from the kit's own live controller
(`CameraPpgSession._controller`, `lib/src/api/camera_ppg_session.dart:125`, created at
`ResolutionPreset.low` and `initialize()`d in `start()`). The controller is owned inside
the session and deliberately never crosses the barrel ("no `camera` type crosses the
API", note 07).

## The change

Add a preview surface to the kit that returns a **`Widget`** (a `package:flutter` type
— clean across the barrel) backed by the session's internal controller, without
exposing the `CameraController` itself:

- `CameraPpgSession`: a method e.g. `Widget? buildPreview()` that returns
  `CameraPreview(_controller!)` when `_controller != null && _controller!.value.isInitialized`,
  else `null`. Export via the barrel (`lib/camera_ppg_kit.dart`). The returned widget
  wraps `package:camera` internally but the signature is `Widget?` — no `camera` type
  leaks.
- Example `source_screen.dart`: render the preview in a `SectionCard` (aspect-ratio
  boxed), gated on lifecycle state — placeholder ("no preview — start the source") when
  `buildPreview()` is null (idle / pre-lock / during the auto-detect probe, where the
  controller flips between sensors), the live texture once locked and measuring.

## Guards

- Preview must coexist with the running `startImageStream` on the same controller — the
  `camera` plugin supports preview + image stream together; at `ResolutionPreset.low`
  the cost is negligible. Confirm on device it does not starve the frame stream (FPS is
  load-bearing, note 13/CLAUDE.md) — if it measurably drops FPS, that is a finding to
  report, not to hide.
- Preview lifetime is bound to the controller: null before lock and after stop; the
  example must handle null every rebuild, never cache a stale widget across a stop.
- This is an **additive kit-surface** change — it must be enumerated in note 19's API
  freeze (Phase 10). It is legitimately part of the kit surface (mind_mobile will want a
  "press your finger" preview too), not example-only, even though the immediate driver
  is verification.
- Do not expose the raw `CameraController` — only the `Widget?`. Keep the frame-path /
  teardown invariants untouched (notes 07/13); this only reads the existing controller.

## Verify

- On device: Start → the Source screen shows the live view of the locked lens; the
  finger over the lens fills the frame red. Stopping clears it to the placeholder.
- Cross-check against the halving hypothesis: with the preview confirming a clean,
  fully-covered lens, re-record calibration and see whether the doubling persists (feeds
  the de-halving re-evaluation — notes 29/30).
