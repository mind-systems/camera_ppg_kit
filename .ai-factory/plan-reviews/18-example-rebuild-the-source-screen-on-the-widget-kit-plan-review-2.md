## Plan Review — Example: rebuild the Source screen on the widget kit (round 2)

**Plan:** `.ai-factory/plans/18-example-rebuild-the-source-screen-on-the-widget-kit.md`
**Governing spec:** `.ai-factory/notes/26-source-screen-rebuild.md` (with notes 22, 23, 25)
**Files Reviewed:** plan + `example/lib/screens/source_screen.dart`, the full `example/lib/widgets/` kit (`widgets.dart`, `section_card.dart`, `state_banner.dart`, `status_chip.dart`, `status_color.dart`, `metric_row.dart`, `async_states.dart`), `example/lib/providers/stream_providers.dart`, notes 22/23/25/26, prior review-1
**Risk Level:** 🟢 Low

### Context Gates
- **Roadmap linkage** — OK. Milestone resolves to note 26; the plan's four tasks map 1:1 onto note 26's Details bullets (`StateBanner`, Control card, Signal card, Camera-override card, `[debug]` tuning card, error banner). Presentation-only scope and the "kit `lib/` / recorder / service untouched" guard are preserved.
- **note 23 (open-ended session)** — OK, already landed. `source_screen.dart:_stateBanner` (lines 151–156) has exactly the four arms the plan enumerates (`idle`/`warmup`/`measuring`/`poorSignal`), no `done`. The plan's "do not add a `done`/Complete arm" instruction matches reality.
- **note 25 (widget kit)** — OK. Every symbol the plan names exists and matches the signature used:
  - `SectionCard({required title, subtitle?, required child})` — required `title` rendered as a bold header (confirms the doubled-header risk the plan now handles).
  - `StateBanner(label, color)`, `StatusChip(label, color)` — positional, enum-agnostic.
  - `LabelRow(label, value)` — plain string value (correct for `presenceLabel`).
  - `AsyncEmpty(message)`, `AsyncError(error)`, `AsyncLoader({caption?})`.
  - `status_color.dart`: `idleColor`/`pendingColor`/`goodColor`/`fairColor`/`poorColor` + `qualityColor(SignalQuality?)`. All present; barrel `widgets.dart` re-exports all.
- **RULES.md / ARCHITECTURE.md / skill-context** — no `.ai-factory/RULES.md`; ARCHITECTURE.md carries no constraint this presentation task crosses; no `skill-context/aif-review/SKILL.md` present.

### Round-1 issues — both resolved
1. **Doubled `[debug] tuning` header — FIXED.** Task 4 now names the resolution explicitly: keep `SectionCard(title: '[debug] tuning')` as the sole header and change the inner `ExpansionTile`'s `title` to a neutral collapse control (`Text('Tuning knobs')`). This matches note 26 ("an `ExpansionTile` inside is fine") and removes the verbatim double-render of source_screen.dart:325.
2. **Under-specified pre-signal async mapping — FIXED.** Task 3 now states the mapping precisely: `qualityProvider`/`fingerPresenceProvider` sit in `loading` (not a null-data state) until first emit, so a plain `.when` would render `AsyncLoader` (spinner). The plan directs mapping the pre-signal `loading` case to `AsyncEmpty('waiting for signal…')` to satisfy the Verify line, gates the SQI `StatusChip` on `quality`, and keeps finger-presence as a `LabelRow` with the existing `null → 'unknown'` fallback. This is consistent with the actual `StreamProvider<SignalQuality>` / `StreamProvider<FingerPresence>` shapes in `stream_providers.dart`.

### Verified assumptions (no issue)
- Import `../widgets/widgets.dart` is correct relative to `example/lib/screens/source_screen.dart`.
- Task 1 color mapping preserves current behavior exactly: `idle→idleColor(grey)`, `warmup→pendingColor(blue)`, `measuring→goodColor(green)`, `poorSignal→fairColor(orange)` — identical to the current inline switch. The plan's added "orange is intentional, `poorColor`/red reserved for the error banner" comment forestalls a future mis-correction. Good.
- Error banner: `error.type.name`, `error.message`, `error.permanentlyDenied` are the exact fields the current `_errorBanner` reads (lines 186–191); routing the error text through `StateBanner(..., poorColor)` followed by the retained full-width "Retry" `OutlinedButton` (with `ppgTap('source_retry')`) preserves behavior. `_lastError` gating in `build` is explicitly kept.
- Behavioral invariants held: `_lastError` lifecycle, `_start`/`_checkAndRequestCameraPermission` permission flow, `isRunning`/`canStop` predicates, `_loadCameras`/`_selectCamera` + dropdown drop-stale-selection logic, the value-keyed `ValueKey('$label-$value')` re-seed on tuning fields, and every `ppgTap(...)` call. No `sessionConfigProvider` read/write change.

### Minor observations (non-blocking)
- Task 3 wraps the SQI read in async states but leaves finger-presence as a plain `LabelRow` off `.value` (no spinner). That is a deliberate, reasonable asymmetry the plan calls out; just ensure the `LabelRow`'s `null → 'unknown'` path reads as an acceptable "pre-signal" label rather than a spurious state (it does — "unknown" is the honest pre-signal value).
- Start/Stop already live in a `Row`+`Expanded` today; Task 3's "Expanded inside a Row (or stacked full-width)" latitude is fine and changes nothing behavioral.

### Positive Notes
- Dependency-ordered decomposition (mapping → banners → cards → recompose+cleanup), each task scoped to the single file.
- Task 4 explicitly deletes now-dead inline helpers/imports and verifies a clean compile — good recomposition hygiene.
- The plan is precise about the two subtle traps in this widget kit (required `title` forcing a doubled header; `StreamProvider` `loading` ≠ empty), which are exactly the two things a naive port would get wrong.

The plan is sound, faithful to note 26, and both round-1 findings are closed in the plan text. No blocking issues remain.

PLAN_REVIEW_PASS
