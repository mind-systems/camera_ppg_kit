# Code Review: Preview square in the Signal card + reset on Stop (review 2)

## Scope
Reviewed `git diff HEAD`. The only code change is `example/lib/screens/source_screen.dart`;
the remaining staged entries are planning artifacts (`ROADMAP.md`, note 37, plan +
plan-review + review-1 files). Read the changed file in full and re-checked its
collaborators: `services/camera_ppg_service.dart`, `services/source_lifecycle.dart`,
`providers/stream_providers.dart`, `widgets/section_card.dart`, `widgets/async_states.dart`.

## Change since review 1
The single low-severity finding from review 1 has been fixed: the two stale
`` `_previewCard()` `` mentions in `_cameraOverrideCard`'s dartdoc now read
`_signalCard()`'s live preview square (`source_screen.dart:322,325`). Confirmed no
`_previewCard` reference remains anywhere in `example/lib`. The executable code is
otherwise identical to the version verified in review 1.

## Correctness assessment (re-confirmed)

- **Stop-reset bug fixed.** Gating the SQI area on `!lifecycle.isActive` forces
  `AsyncEmpty('waiting for signal…')` the moment `stopMeasurement()` drives lifecycle to
  `stopping`→`idle`, so the retained `qualityProvider` `AsyncData` ("SQI: good") no longer
  leaks past Stop. Matches `CameraPpgService.stopMeasurement()` and `_foldLifecycle()`'s
  late-emit guard.
- **Preview gating is use-after-dispose-safe.** `session?.buildPreview()` is read only
  while `lifecycle.isActive` (`warmup`/`measuring`/`poorSignal`) — never during
  `starting`/`stopping`, when the controller may be uninitialised or mid-`dispose()`. The
  `Widget?` null-return still yields the placeholder if the controller is briefly absent.
  This is strictly safer than the removed `_previewCard()`, which read `buildPreview()`
  unconditionally.
- **Layout is sound.** `Row` → two `Expanded` → `AspectRatio(1)` inside `SectionCard`'s
  plain `Column` (no `IntrinsicHeight/Width`) within the screen's `ListView`: bounded
  cross-axis width, `AspectRatio` derives finite height from the `Expanded` width, no
  intrinsic traversal, no unbounded-constraint or overflow risk. `crossAxisAlignment.start`
  top-aligns the shorter SQI child against the taller square.
- **Static analysis clean.** `flutter analyze lib/screens/source_screen.dart` → "No issues
  found!".

## Non-blocking observation (unchanged, out of scope)
On a second run, `warmup` is `active`, so the SQI chip can briefly show the prior run's
retained "SQI: good" before the first fresh emit. This is pre-existing behaviour, explicitly
outside this task's Stop-reset scope, and the change strictly improves on the old
never-reset behaviour. No action required here.

## Verdict
Correct and complete. The prior finding is resolved and no new issues were introduced.

REVIEW_PASS
