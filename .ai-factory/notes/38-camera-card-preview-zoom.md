# Camera card: move the preview square in (shrunk), coexisting with the dropdown

**Date:** 2026-07-03
**Source:** conversation context (consolidate camera controls)

## Why here

The camera is configured in the **Camera override card** (`_cameraOverrideCard` in
`source_screen.dart`), so the preview belongs there with the other camera controls.
This is a developer example app — controls sit side by side, not a minimal end-user UX.

## Current state

- Preview square currently lives in the Signal card (`_signalCard`, note 37) as an
  `Expanded` + `AspectRatio(1)` — a square ≈ half the card width (~150 logical px), too
  large.
- `_cameraOverrideCard` holds a Refresh button, the resolved-lens label (note 36), and a
  `DropdownButton` of `availableCameras()`.

## The change (example only — no kit surface change)

- Move the preview square **out of** `_signalCard` and **into** `_cameraOverrideCard`,
  and **shrink it ~1.5×**: replace the proportional `Expanded` with a **fixed square**
  ≈ 96–104 logical px, still `ClipRRect` rounded + `service.buildPreview()` with a blank
  placeholder when null. Fixed size, not `Expanded`, so it sits neatly beside the other
  controls instead of stretching / dominating.
- The Signal card reverts to just the SQI chip (full-width again) + the `Finger`
  `LabelRow`, keeping note 37's Stop-reset gating for the SQI area.
- Arrange the camera card cleanly, e.g. a top row with Refresh + the resolved-lens label
  on the left and the small fixed preview square on the right, the dropdown full-width
  below. Preview coexists with the dropdown — not a replacement.
- Gate the preview on lifecycle (note 33 / `service.isMeasuring`): live texture while
  measuring, placeholder otherwise, blanking on Stop (never cache a stale widget).

## Verify

- Camera card shows Refresh + resolved-lens label + a small live preview square + the
  dropdown together; the square is clearly smaller than before and does not dominate.
- Preview blanks on Stop; Signal card still resets its SQI on Stop (note 37 intact) and
  no longer shows a preview.

## Guards

- Example presentation only — no kit `lib/` change, no `MeasurementState` change (no
  `done`, note 23).
- Read `buildPreview()` fresh each build; gate on lifecycle, not on the last quality
  emit.
