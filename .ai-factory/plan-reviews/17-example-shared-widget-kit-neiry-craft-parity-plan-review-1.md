# Plan Review — Example: shared widget kit (neiry-craft parity)

**Plan:** `.ai-factory/plans/17-example-shared-widget-kit-neiry-craft-parity.md`
**Spec:** `.ai-factory/notes/25-example-widget-kit.md`
**Roadmap line:** Phase 7 — "Example: shared widget kit (neiry-craft parity)"
**Risk Level:** 🟢 Low

## Scope & Intent

Foundation-only task: extract the inline UI patterns repeated across the three
example screens into a dependency-free `example/lib/widgets/` kit, consumed later
by notes 26–28. No kit `lib/` change, no screen rewire, no runtime/security
surface, no proto or migration. Correctly routed to `camera_ppg_kit` local
planning (kit is outside root orchestration).

## Context Gates

- **Architecture / base rules (`.ai-factory/rules/base.md`):** The barrel rule
  ("Public API surface is the `lib/camera_ppg_kit.dart` barrel — re-export from
  `lib/src/` only") governs the *kit*, not the example. Task 6's
  `example/lib/widgets/widgets.dart` re-export barrel is a faithful mirror of
  that convention for the example's local set — no boundary violation. **PASS.**
- **Roadmap alignment:** Plan maps 1:1 onto the open Phase-7 milestone; guards
  ("kit `lib/` untouched", "screens rebuilt in 26–28, not here") match the
  roadmap line and spec Guards verbatim. **PASS.**
- **RULES.md / skill-context:** No `.ai-factory/RULES.md` and no
  `.ai-factory/skill-context/aif-review/SKILL.md` present — nothing to enforce.

## Correctness — extraction fidelity (verified against source)

Each extraction was checked against the actual current screens:

- **StateBanner** matches `source_screen.dart:_stateBanner` / `streams_screen.dart:_stateBanner`
  exactly: `width: double.infinity`, `EdgeInsets.all(12)`, `color.withValues(alpha: 0.1)`
  fill, `BorderRadius.circular(8)`, `Border.all(color: color)`, centered bold
  `fontSize: 16` label in `color`. ✔
- **StatusChip** matches the inline `_qualityAndPresenceRow` chip:
  `backgroundColor: color.withValues(alpha: 0.15)`, bold `labelStyle` in `color`. ✔
- **Color map** (good→green, fair→orange, poor→red, idle→grey, pending→blue)
  matches both the `_qualityAndPresenceRow` quality switch and the `_stateBanner`
  state switch (warmup→blue = pending). ✔
- **SectionCard 16/12/8 rhythm** matches the plan's stated card rhythm and the
  spec. ✔
- **API surface:** `SignalQuality` is exported from the kit barrel (confirmed in
  `lib/camera_ppg_kit.dart`), so Task 1's `import 'package:camera_ppg_kit/camera_ppg_kit.dart'`
  resolves. `withValues` is available at the pinned SDK (`^3.11.0`). `const`
  constructors are achievable for all proposed widgets (they only store
  `String`/`Color`/`Widget` fields). ✔

## Assessment of the one deliberate spec deviation

The spec's Verify clause asks for "a throwaway smoke screen … renders with the
16/12/8 rhythm." Task 7 **declines** to build it, arguing a demo screen would
violate the "foundation only, screens untouched" guard and treating the smoke
screen as a manual sanity check instead. This is the right call and is well
reasoned — a committed smoke screen would be dead code and contradict the guard.
Substituting `flutter analyze` (the spec's other Verify clause, "the widgets
compile") as the automated gate is sound. No action needed; flagged only so the
deviation is on record.

## Minor, non-blocking observations

None of these block implementation:

1. **Task 5 ↔ Task 1 dependency is undeclared.** `AsyncError` is described as
   rendering its text "in the poor/red color." If the implementer pulls that from
   Task 1's `poor` constant, Task 5 depends on Task 1, but only Task 4 declares
   that dependency. Trivially resolved either way (import `status_color.dart`, or
   use `Colors.red` inline) — just make the choice explicit so `async_states.dart`
   doesn't dangle a reference. The commit plan (Task 1 lands in Commit 1, Task 5
   in Commit 2) already orders them safely.

2. **`MetricRow` is spec-driven, not extracted-verbatim.** No current screen uses
   a fixed-`labelWidth` label→value row (the debug fields use `Expanded(Text)`
   instead). That's fine — `MetricRow` is a new foundation primitive the rebuilds
   (26–28) will consume, and its signature comes straight from the spec. Noting
   so "match the exact patterns already inlined" isn't misread as requiring an
   existing call site.

3. **`flutter analyze` is whole-project.** It analyzes the entire example
   package, so pre-existing findings elsewhere could surface. Task 7 already
   scopes acceptance correctly ("the new `example/lib/widgets/` files produce no
   analyzer errors/warnings") — just apply that qualifier and don't get blocked by
   unrelated pre-existing noise. Unreferenced *public* widgets/consts will not be
   flagged by default lints, so the not-yet-imported kit compiles clean.

## Positive Notes

- Extraction values were transcribed precisely from the live screens — no drift
  between plan and code.
- Guards are explicit and correct: no `ThemeData`, no new deps, no logging in
  leaf widgets, kit `lib/` untouched, screens deferred to 26–28.
- Widgets kept enum-agnostic (callers pass the color from the Task 1 map) is the
  right seam — keeps `StateBanner`/`StatusChip` reusable and confines the
  `MeasurementState`→color switch to the screens that own state semantics.
- Commit plan respects the global rule (sentence case, no type prefixes) and
  sequences dependencies safely.

The plan is solid and ready to implement; the three observations above are
optional polish, not corrections.

PLAN_REVIEW_PASS
