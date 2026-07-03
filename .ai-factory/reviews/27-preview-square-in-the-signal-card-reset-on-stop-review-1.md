# Code Review: Preview square in the Signal card + reset on Stop (review 1)

## Scope
Reviewed the code change in `example/lib/screens/source_screen.dart` (the only
non-artifact code change in `git diff HEAD`). The other staged changes are planning
artifacts (`ROADMAP.md`, notes, plan/plan-review JSON+MD) — no code.

Read the full changed file plus its collaborators: `services/camera_ppg_service.dart`,
`services/source_lifecycle.dart`, `providers/stream_providers.dart`,
`widgets/section_card.dart`, `widgets/async_states.dart`.

## What the change does
- Removes the standalone `_previewCard()` method and its `build()` invocation.
- Recomposes `_signalCard(SourceLifecycle lifecycle)` so its top is a `Row` of two
  `Expanded` children — SQI display on the left, a square `AspectRatio(1)` live preview
  (`ClipRRect` rounded, fed by `session?.buildPreview()`) on the right — with the
  `Finger` `LabelRow` unchanged below.
- Gates both the SQI area and the preview on `lifecycle.isActive`: when not active
  (`idle`/`starting`/`stopping`) both render the "waiting…"/placeholder state regardless
  of the retained `qualityProvider`/session value; only while active
  (`warmup`/`measuring`/`poorSignal`) are the live values rendered.

## Correctness assessment

**The Stop-reset bug fix is correct.** The stale "SQI: good" survived because
`qualityProvider` (a `StreamProvider` over the long-lived `qualityStream`) retains its
last `AsyncData` and nothing repaints it on Stop. Gating on `!active` forces
`AsyncEmpty('waiting for signal…')` the instant `stopMeasurement()` drives lifecycle to
`stopping`→`idle`, independent of the retained stream value. Verified against
`CameraPpgService.stopMeasurement()` (sets `stopping`, then `idle`) and
`_foldLifecycle()` (ignores late kit emits once `stopping`/`idle`).

**The preview gating is not just correct but strictly safer than before.** The old
`_previewCard()` read `session?.buildPreview()` unconditionally, so during the `stopping`
teardown window it could build a `CameraPreview` over a controller mid-`dispose()`. The
new code only reads `buildPreview()` while `lifecycle.isActive`, so it is never invoked
during `starting`/`stopping`; the session/controller is alive throughout the active
states. `buildPreview()`'s own `Widget?` null-return still yields the placeholder if the
controller is briefly uninitialised at the start of `warmup`. No null-deref, no
use-after-dispose.

**Layout is sound — no unbounded-constraint or overflow risk.** The `Row` lives inside
`SectionCard`'s plain `Column` (no `IntrinsicHeight`/`IntrinsicWidth`), itself inside the
screen's `ListView`, so cross-axis width is bounded. Each `Expanded` gives its child a
bounded width; `AspectRatio(1)` under a bounded-width / unbounded-height constraint
derives a finite height from the width — the well-defined AspectRatio case, no intrinsic
traversal. `crossAxisAlignment.start` top-aligns the shorter SQI child against the taller
square. `flutter analyze lib/screens/source_screen.dart` → "No issues found!".

## Findings

### 1. [LOW — documentation] Stale `_previewCard()` references in `_cameraOverrideCard` dartdoc
`source_screen.dart:322` and `:325` still refer to `` `_previewCard()` `` ("the text
complement to `_previewCard()`'s live texture" / "the same `ref.watch(lifecycleProvider)`
rebuild `_previewCard()` already relies on"), but this diff deletes that method — the live
preview now lives inside `_signalCard()`. These are backtick code spans, not `[...]`
doc-link references, so they raise no analyzer/dartdoc warning (confirmed: analyze is
clean), but they now point at a symbol that no longer exists. Non-blocking; update the two
mentions to reference the preview square in the Signal card (`_signalCard()`).

## Non-blocking observation (not a defect in this diff)
On the **second and subsequent** runs, `warmup` is `active`, so the SQI side renders
`qualityAsync.when(data: …)`. Because `qualityProvider` retains the prior run's last
`SignalQuality`, the chip can briefly show a stale "SQI: good" during `warmup` before the
first fresh emit arrives. This is **pre-existing** (the old `_signalCard()` had no
lifecycle gate at all and showed the stale value even while idle — precisely the bug this
task fixes) and is explicitly out of the task's scope, which targets the Stop→idle reset.
The change strictly improves the situation. Flag only if a future task wants the SQI to
show "waiting…" through `warmup` until the first new emit; it would need the service to
push a reset onto `qualityStream` on stop/start, or the card to also treat `warmup` as
non-live for SQI. No action required here.

## Verdict
Functionally correct; the Stop-reset bug is fixed and the layout is safe. One low-severity
documentation staleness finding (stale `_previewCard()` mentions in a neighbouring
dartdoc).
