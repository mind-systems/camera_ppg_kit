# Code Review (round 2): Camera card — move the preview square in (shrunk), coexist with dropdown

**Scope reviewed:** `example/lib/screens/source_screen.dart` (only code file changed; the `.json`/`.md`/`ROADMAP.md` plan artifacts and the plan-review/review-1 files are non-code and were not reviewed for bugs).

**Verification:** `flutter analyze example/lib/screens/source_screen.dart` → *No issues found*.

## Round-1 finding — resolved

The sole round-1 finding (low/cosmetic: the `_loadingCameras` `CircularProgressIndicator` stretched into a flattened oval once the Refresh control was wrapped in `Expanded`) is fixed. The loading branch is now `Align(alignment: Alignment.centerLeft, child: SizedBox(14×14, CircularProgressIndicator(...)))` (source_screen.dart:332-340), so the spinner renders at its natural 14×14 size, left-aligned within the `Expanded`, while the `TextButton` branch still gets the full left column. Correct, minimal fix.

## Summary

The change implements plan 28 exactly and is correct:

- **Task 1 (Signal card):** the preview `Row`/`Expanded`/`AspectRatio` layout is gone; the lifecycle-gated SQI block is now the direct full-width child of the `Column`, with the `Finger` `LabelRow` unchanged and the note-37 Stop-reset gating (`final active = lifecycle.isActive;` → `!active` check) preserved. The now-unused `final preview = ...` line was removed from this method; `active` remains referenced (no dead-variable/lint warning).
- **Task 2 (Camera-override card):** `active` + a fresh, uncached `ref.read(...).session?.buildPreview()` are re-derived here, gated on `lifecycle.isActive` exactly as before. The fixed `SizedBox(100×100)` (within the specified 96–104 px range) with `ClipRRect(borderRadius: 8)` and `preview ?? const AsyncEmpty('no preview')` sits to the right of the Refresh control; the dropdown and `Locked lens` row remain full-width below — coexists, does not replace.

No kit `lib/` change, no `MeasurementState`/`buildPreview()` signature change — the Phase-10 freeze is respected. Blank-on-Stop rides the existing `ref.watch(lifecycleProvider)` rebuild in `build()`, so the placeholder returns the instant lifecycle leaves `isActive`.

Runtime checks — no issues:
- `AsyncEmpty` (Center + `Column(mainAxisSize.min)`, ~46 px tall, short text) fits inside the 100×100 box — no overflow.
- `CameraPreview` receives tight 100×100 constraints; its internal `AspectRatio` short-circuits on tight constraints and fills the box (same square-fit behavior the prior `AspectRatio(1)` wrapper produced) — no regression, no overflow.
- The Row (`crossAxisAlignment: start`, Expanded + 12 px gap + 100 px preview) lays out cleanly with the 100 px preview setting the row height; the top-aligned Refresh control is intentional.

No bugs, security issues, correctness problems, or overflows found.

REVIEW_PASS
