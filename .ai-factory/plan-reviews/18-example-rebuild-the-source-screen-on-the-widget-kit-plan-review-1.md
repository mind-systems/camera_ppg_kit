## Plan Review — Example: rebuild the Source screen on the widget kit

**Plan:** `.ai-factory/plans/18-example-rebuild-the-source-screen-on-the-widget-kit.md`
**Governing spec:** `.ai-factory/notes/26-source-screen-rebuild.md` (with notes 22, 23, 25)
**Files Reviewed:** plan + `example/lib/screens/source_screen.dart`, the full `example/lib/widgets/` kit, `example/lib/providers/stream_providers.dart`, notes 22/23/25/26, ROADMAP
**Risk Level:** 🟢 Low

### Context Gates
- **Roadmap linkage** — OK. The milestone ("Example: rebuild the Source screen on the widget kit") resolves to note 26, and the plan's four tasks map 1:1 onto note 26's Details bullets (StateBanner, Control card, Signal card, Camera-override card, `[debug]` tuning card, error banner). Presentation-only scope and the "kit `lib/` / recorder / service untouched" guard are preserved.
- **note 23 (open-ended session)** — OK, and already landed: `grep MeasurementState.done` returns no hit in `source_screen.dart`, and the current `_stateBanner` switch has exactly the four arms the plan enumerates. The plan's explicit "do not add a `done`/Complete arm" instruction is correct and matches reality.
- **note 25 (widget kit)** — OK. Every symbol the plan names exists in `example/lib/widgets/`: `SectionCard`, `StateBanner(label,color)`, `StatusChip(label,color)`, `LabelRow(label,value)`, `AsyncLoader/AsyncEmpty/AsyncError`, and the `status_color.dart` constants `idleColor/pendingColor/goodColor/fairColor/poorColor` + `qualityColor(SignalQuality?)`. Barrel `widgets.dart` re-exports all of them.
- **RULES.md / ARCHITECTURE.md** — no `.ai-factory/RULES.md`; ARCHITECTURE.md carries no constraint this presentation task crosses. No `skill-context/aif-review/SKILL.md` present.

### Verified assumptions (no issue)
- Import path `../widgets/widgets.dart` is correct relative to `example/lib/screens/source_screen.dart`.
- Provider names `stateProvider` / `qualityProvider` / `fingerPresenceProvider` / `sessionConfigProvider` and the `presenceLabel` switch all exist as the plan describes.
- Task 1 colour mapping preserves current behaviour exactly: idle→grey (`idleColor`), warmup→blue (`pendingColor`), measuring→green (`goodColor`), poorSignal→orange (`fairColor`). Using `fairColor` (orange, not red) for `poorSignal` is the *current* colour and is deliberate — `poorColor`/red stays reserved for the error banner. Correct, though a one-line "orange is intentional, not `poorColor`" note in the code would prevent a future "shouldn't poorSignal use poorColor?" edit.

### Issues

**1. [WARN — concrete] Task 4 will render the `[debug] tuning` title twice.**
The plan says: `SectionCard(title: '[debug] tuning', ...)` "whose child is the existing `ExpansionTile`". `SectionCard` renders its `title` as a bold header (section_card.dart:28), and the existing `ExpansionTile` also has `title: const Text('[debug] tuning')` (source_screen.dart:325). Nesting them verbatim yields the header string twice — once static, once as the tappable expand control. `SectionCard.title` is required, so it cannot simply be omitted.
Resolution (pick one, implementer's choice): keep `SectionCard(title: '[debug] tuning')` and change the inner `ExpansionTile`'s title to a neutral collapse control (e.g. `Text('Tuning knobs')` or `'Show/Hide'`), **or** keep the `ExpansionTile`'s own title as the sole header and wrap it in a plain `Card`/title-less container rather than a titled `SectionCard`. Note 26 ("render the fields inside a `SectionCard` (an `ExpansionTile` inside is fine)") permits either; the plan should name which to avoid a doubled header.

**2. [WARN — minor] Signal card combines two independent `AsyncValue`s; the "waiting…" mapping is under-specified.**
`qualityProvider` and `fingerPresenceProvider` are `StreamProvider`s that sit in the `loading` state until their first emit — there is no natural null-*data* state before Start, so `.when(data/loading/error)` would surface `AsyncLoader` (a spinner), not `AsyncEmpty('waiting for signal…')`. The plan hedges ("and/or their `.value == null` case … `AsyncLoader`/`AsyncError` as appropriate"), which is acceptable planning latitude, but the implementer must consciously map pre-signal `loading` → `AsyncEmpty('waiting for signal…')` to satisfy the Verify line ("show a waiting… async state before signal arrives"). Also decide how the two streams gate one card (e.g. gate the SQI `StatusChip` on `quality`, render finger via `LabelRow` reusing the existing `null → 'unknown'` fallback). Not a blocker — just flag that the plain `.when` reading would show a spinner, not the required "waiting…" copy.

### Positive Notes
- Task decomposition is clean and dependency-ordered (mapping → banners → cards → recompose+cleanup), each task scoped to the single file.
- The plan correctly preserves every behavioural invariant that matters: `_lastError` lifecycle, `_start`/permission flow, `isRunning`/`canStop` predicates, the value-keyed `ValueKey('$label-$value')` re-seed pattern on the tuning fields, and all `ppgTap(...)` interaction logs — consistent with the example-app's "log every interaction" convention.
- Task 4 explicitly calls for deleting now-dead inline helpers and verifying a clean compile — good hygiene for a recomposition.

The plan is sound and faithful to its spec; the two items above are refinements, not redesigns. Fix issue 1 (doubled title) before implementing.
