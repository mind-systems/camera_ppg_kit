# Code Review: Camera card — move the preview square in (shrunk), coexist with dropdown

**Scope reviewed:** `example/lib/screens/source_screen.dart` (only code file changed; the `.json`/`.md` plan artifacts and the plan-review file are non-code and were not reviewed for bugs).

**Verification:** `flutter analyze example/lib/screens/source_screen.dart` → *No issues found*.

## Summary

The change does exactly what plan 28 specifies and is essentially correct:

- **Task 1 (Signal card):** the preview `Row`/`Expanded`/`AspectRatio` layout is removed; the lifecycle-gated SQI block (`!active ? AsyncEmpty(...) : qualityAsync.when(...)`) becomes the direct full-width child of the `Column`, the `Finger` `LabelRow` is unchanged, and the note-37 Stop-reset gating (`final active = lifecycle.isActive;`, used at the `!active` check) is preserved. The now-unused `final preview = ...` line was correctly deleted from this method. `active` remains referenced, so no dead-variable/lint issue.
- **Task 2 (Camera-override card):** `active` + a fresh `ref.read(...).session?.buildPreview()` are re-derived here (never cached), gated on `lifecycle.isActive` exactly as before. The fixed `SizedBox(width: 100, height: 100)` (in the specified 96–104 px range) with `ClipRRect(borderRadius: 8)` and `preview ?? const AsyncEmpty('no preview')` sits to the right of the Refresh control; the dropdown and `Locked lens` row remain full-width below. Coexists, not replaces — as required.

No kit `lib/` change, no `MeasurementState`/`buildPreview()` signature change — the Phase-10 freeze is respected. The blank-on-Stop behavior rides the existing `ref.watch(lifecycleProvider)` rebuild in `build()`, so the placeholder is shown the instant lifecycle leaves `isActive` — correct and preserved from the prior placement.

No crashes, overflows, security issues, or logic errors found:
- `AsyncEmpty` (Center + `Column(mainAxisSize.min)`, ~46 px tall, short text) fits comfortably inside the 100×100 box — no overflow.
- `CameraPreview` gets tight 100×100 constraints; its internal `AspectRatio` short-circuits on tight constraints and fills the box (same square-fit distortion behavior the prior `AspectRatio(1)` wrapper produced) — no regression, no overflow.

## Findings

### 1. [Low / cosmetic] Refresh loading-spinner now stretches inside the new `Expanded`

`_cameraOverrideCard`, the top Row (source_screen.dart:331-347): to push the fixed preview square to the right edge, the Refresh control was wrapped in `Expanded`. This is correct for the `TextButton` case, but it also now applies to the `_loadingCameras` branch, whose `SizedBox(width: 14, height: 14, child: CircularProgressIndicator(...))` previously rendered at its natural 14×14 size. Inside `Expanded` the child receives a tight width equal to the full left column (~200–250 px on a phone), so the `CircularProgressIndicator` paints into a wide, 14 px-tall box and renders as a flattened/oval arc during camera enumeration.

- **Impact:** purely cosmetic, and only visible during the brief (`<1 s`) `_loadCameras()` window in this hardware-debug example app. No overflow, no crash, no functional effect.
- **Optional fix:** align the spinner instead of letting it stretch, e.g. wrap the loading branch in `Align(alignment: Alignment.centerLeft, child: SizedBox(14, 14, ...))`, or place the spinner/button with a `Spacer()` before the preview rather than an `Expanded` wrapper.

This is a nit, not a blocker; flagging only because the diff changed the spinner's rendering as an incidental side effect of the layout move.
