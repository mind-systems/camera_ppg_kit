# Plan: Camera card: move the preview square in (shrunk), coexist with dropdown

## Context
Relocate the live-camera preview square from the Signal card into the Camera-override card in the example's `source_screen.dart`, shrinking it to a fixed ~96–104 px square so it sits beside Refresh/resolved-lens/dropdown instead of dominating; the Signal card reverts to a full-width SQI chip plus the Finger row. Example-only, no kit `lib/` change.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Move and resize the preview

- [ ] **Task 1: Revert the Signal card to SQI chip + Finger row**
  Files: `example/lib/screens/source_screen.dart`
  In `_signalCard(SourceLifecycle lifecycle)`: remove the preview square and the wrapping `Row`/`Expanded` layout. Restore the SQI area to full width — the existing lifecycle-gated block (`!active ? AsyncEmpty('waiting for signal…') : qualityAsync.when(...)`) becomes the direct child of the `Column` (no longer wrapped in `Expanded` inside a `Row`). Keep the `Finger` `LabelRow` below it unchanged, and keep the note-37 Stop-reset gating on the SQI area (`final active = lifecycle.isActive;`). Delete the now-unused `final preview = active ? ... buildPreview() : null;` line from this method (it moves to Task 2). Update the method's doc comment: drop the "top row is the SQI chip beside a small square live-camera preview" description; the preview no longer lives here.

- [ ] **Task 2: Add the fixed-size preview square into the Camera-override card** (depends on Task 1)
  Files: `example/lib/screens/source_screen.dart`
  In `_cameraOverrideCard(SourceLifecycle lifecycle)`: read the preview fresh each build, gated on lifecycle exactly as the Signal card did — `final active = lifecycle.isActive;` and `final preview = active ? ref.read(cameraPpgServiceProvider).session?.buildPreview() : null;` (never cache across builds; blanks on Stop because the `ref.watch(lifecycleProvider)` rebuild in `build()` drives it). Place a **fixed** square (not `Expanded`/`AspectRatio`) at the right of the existing top Row that holds Refresh: wrap Refresh in an `Expanded` on the left, then a `SizedBox(width: 100, height: 100)` (within the ~96–104 px range) on the right containing `ClipRRect(borderRadius: BorderRadius.circular(8), child: preview ?? const AsyncEmpty('no preview'))`. Leave the `DropdownButton` full-width below and the `Locked lens` `LabelRow` beneath it — the preview coexists with them, it is not a replacement. Update the method doc comment to note the preview square now lives here (currently it references `_signalCard()`'s preview as the visual complement to the resolved-lens text).

## Notes
- No kit `lib/` change, no `MeasurementState`/`buildPreview()` signature change — presentation only (note 38 guards; Phase-10 API freeze).
- Preview is read via `ref.read(...).session?.buildPreview()` fresh on every build and gated on `lifecycle.isActive`, so it shows a live texture only in `warmup`/`measuring`/`poorSignal` and reverts to the `'no preview'` placeholder the instant Stop is pressed (note 33 lifecycle gate, note 38 blank-on-Stop).
