## Code Review Summary

**Files Reviewed:** 1 plan (`28-camera-card-move-the-preview-square-in-shrunk-coexist-with-dropdown.md`) against `example/lib/screens/source_screen.dart`, the widget kit, the service/session API, spec note 38, and ROADMAP.md
**Risk Level:** 🟢 Low

### Context Gates

- **ROADMAP linkage — OK.** The plan heading matches ROADMAP.md line 73 exactly (milestone 28: "Camera card: move the preview square in (shrunk), coexist with dropdown"), the only unchecked item in that chain. It cites its `Spec:` note (`notes/38-camera-card-preview-zoom.md`) and the upstream notes 35/37 it depends on. All present on disk.
- **Governing spec (note 38) — OK.** Plan faithfully implements the spec: move the preview out of `_signalCard` into `_cameraOverrideCard`, shrink from `Expanded`+`AspectRatio(1)` to a fixed ~96–104 px square, revert the Signal card to a full-width SQI chip + Finger row keeping note-37 Stop-reset, gate the preview on lifecycle so it blanks on Stop, read `buildPreview()` fresh each build. Chosen `SizedBox(width: 100, height: 100)` is inside the spec's 96–104 px range.
- **ARCHITECTURE.md — OK.** Change is example-only (`example/lib/`), touches no kit `lib/` surface, and introduces no `MeasurementState`/`buildPreview()` signature change — consistent with the note-19/Phase-10 API freeze the plan cites. No architectural boundary crossed.
- **RULES.md / skill-context — N/A.** No `.ai-factory/RULES.md` and no `.ai-factory/skill-context/aif-review/SKILL.md` present in this repo.

### Critical Issues

None. Every API and widget the plan names was verified against the codebase:
- `ref.read(cameraPpgServiceProvider).session` — `CameraPpgService.session` getter exists (`camera_ppg_service.dart:93`).
- `session?.buildPreview()` returns `Widget?` (`camera_ppg_session.dart:193`), so `preview ?? const AsyncEmpty('no preview')` type-checks.
- `session?.resolvedCamera` exists (`camera_ppg_session.dart:176`) and is already used by `_cameraOverrideCard`.
- `AsyncEmpty`, `SectionCard`, `LabelRow`, `StatusChip`, `AsyncError` are all exported by `widgets/widgets.dart`.
- `lifecycle.isActive` is already in use in both methods; deleting the `preview` line in `_signalCard` leaves `active` still referenced by the SQI block (no unused-variable warning), and re-declaring `active`/`preview` in `_cameraOverrideCard` does not collide with its existing `locked`/`resolved` locals.
- File path `example/lib/screens/source_screen.dart` is correct; both target methods (`_signalCard`, `_cameraOverrideCard`) exist with the exact structure the plan describes.

Task dependency (Task 2 depends on Task 1) is correct — Task 1 removes the preview from `_signalCard`, Task 2 re-homes it — and both edit the same file, so ordering matters as stated.

### Minor Notes (non-blocking)

1. **Refresh-row wrapping (Task 2).** The plan says "wrap Refresh in an `Expanded`". The current top Row child is an `if (_loadingCameras) …spinner… else …TextButton…` conditional, not a bare `TextButton`. The implementer should wrap that whole conditional in the `Expanded` (or make it the `Expanded`'s child), not only the `TextButton` branch, so the spinner state also lays out correctly. Straightforward, but worth stating so the loading branch isn't left outside the `Expanded`.
2. **Vertical alignment of the row.** With a 100 px-tall preview on the right and a short Refresh button on the left, the Row's default `crossAxisAlignment: center` will vertically center the button against the tall square. That is cosmetically fine for a developer example; flag only if a top alignment is preferred.
3. **Aspect-ratio distortion.** Dropping `AspectRatio(1)` and forcing `CameraPreview` into a fixed square `SizedBox` will stretch the texture to the square — but this is the intended "shrunk fixed square" design (note 38), and note-37's `AspectRatio(1)` already squared a non-square preview, so it is the same behavior class, not a regression.
4. **Layout vs. spec's suggested arrangement.** Note 38 suggests ("e.g.") putting Refresh *and* the resolved-lens label on the left with the preview on the right. The plan keeps the `Locked lens` `LabelRow` in its current position (below the dropdown) and only co-locates Refresh with the preview. Acceptable — the spec phrasing is a non-binding example — but noted in case the reviewer wanted the resolved-lens label moved up too.

### Positive Notes

- The plan is precise about the lifecycle gate rationale (read fresh via `ref.read(...).session?.buildPreview()`, never cache, blank-on-Stop rides the existing `ref.watch(lifecycleProvider)` rebuild) and correctly preserves note-37's Stop-reset semantics.
- It explicitly calls out updating both method doc comments (removing the preview description from `_signalCard`, adding it to `_cameraOverrideCard`), which keeps the heavily-annotated doc comments in this file honest — a common thing plans forget.
- Scope is correctly fenced to the example app with an explicit "no kit `lib/` change / API-freeze" guard, matching the spec and roadmap contract.

The plan is accurate to the codebase, correctly scoped, dependency-ordered, and faithful to its governing spec. The minor notes are implementation hygiene, not blockers.

PLAN_REVIEW_PASS
