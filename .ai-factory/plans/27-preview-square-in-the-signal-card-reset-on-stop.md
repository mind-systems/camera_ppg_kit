# Plan: Preview square in the Signal card + reset on Stop

## Context
Fold note 35's live camera preview into the Source screen's Signal card as a small
square beside the SQI chip (superseding note 35's standalone preview card), and fix the
bug where the card keeps showing the last "SQI: good" and frozen preview after Stop by
gating the SQI area + preview on the source lifecycle instead of the last stream value.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Recompose the Signal card

- [x] **Task 1: Fold the preview square into `_signalCard()` and remove the standalone preview card**
  Files: `example/lib/screens/source_screen.dart`
  Recompose `_signalCard()` so its top is a `Row` of two ~equal-width children:
  - **Left** — the existing SQI display (currently the first child of the `Column`:
    `qualityAsync.when(data: StatusChip('SQI: ${quality.name}', qualityColor(quality)), loading: AsyncEmpty('waiting for signal…'), error: AsyncError(error))`).
  - **Right** — a small **square** preview: `AspectRatio(aspectRatio: 1)` wrapped in a
    `ClipRRect(borderRadius: BorderRadius.circular(8))`, fed by
    `ref.read(cameraPpgServiceProvider).session?.buildPreview()` read **fresh on every
    build** (never cached across Stop). When `buildPreview()` returns `null`, render a
    placeholder in the square (e.g. `AsyncEmpty('no preview')`).
    Give each side `Expanded` (roughly SQI-chip width each) so the preview is a small
    square, not a full-width video panel.
  The `LabelRow('Finger', presenceLabel)` stays **exactly as today** as its own row below
  the SQI+preview row (keep the existing `SizedBox(height: 8)` spacer before it).
  Then delete the now-superseded standalone `_previewCard()` method and its invocation +
  following spacer in `build()` (`_previewCard(), const SizedBox(height: 16),`) so the
  preview lives only inside the Signal card. Reuse `_previewCard()`'s existing doc-comment
  rationale (fresh read each build, placeholder pre-lock) in the recomposed square.

### Phase 2: Reset on Stop

- [x] **Task 2: Gate the SQI area + preview on lifecycle so Stop returns them to "waiting…"/placeholder** (depends on Task 1)
  Files: `example/lib/screens/source_screen.dart`
  Pass the already-computed `lifecycle` (from `ref.watch(lifecycleProvider)` in `build()`)
  into `_signalCard(SourceLifecycle lifecycle)` and update the call site
  (`_signalCard(lifecycle)`). Gate on lifecycle, not on the last quality emit:
  - When the source is **not running** (use `!lifecycle.isActive` — i.e. `idle`,
    `starting`, or `stopping`), render the SQI side as `AsyncEmpty('waiting for signal…')`
    and the preview square as its placeholder, regardless of what `qualityProvider` still
    holds.
  - When `lifecycle.isActive` (`warmup`/`measuring`/`poorSignal`), render the live
    `qualityAsync.when(...)` SQI display and the `session?.buildPreview()` square as in
    Task 1 (`buildPreview()`'s own `null`-fallback still shows the placeholder until the
    controller is initialized).
  This fixes the bug: pressing Stop moves `lifecycle` to `stopping`→`idle`, so the SQI
  chip clears from "SQI: good" back to "waiting for signal…" and the preview blanks to its
  placeholder instead of freezing the last value; Start again repopulates both. Keep the
  `Finger` `LabelRow` ungated (identical to today). Do not reintroduce a `done` arm
  (note 23) and do not touch the kit `lib/` (note 35 already shipped `buildPreview()`).
