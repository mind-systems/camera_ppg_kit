## Code Review Summary

**Files Reviewed:** 1 plan (`19-example-rebuild-the-streams-screen-on-the-widget-kit.md`) against 8 codebase files (target screen, sibling `source_screen.dart`, the 6-file widget kit, `stream_providers.dart`)
**Risk Level:** 🟢 Low

### Context Gates

- **Roadmap** (`ROADMAP.md:54`): ✅ Matched. The plan's `# Plan:` heading maps to the milestone "Example: rebuild the Streams screen on the widget kit" (still `[ ]`). Governing spec `Spec: .ai-factory/notes/27-streams-screen-rebuild.md` exists and the plan is a faithful expansion of it — BPM headline card, artifact-flagged live-RR card, SQI/finger `StatusChip`s, `StateBanner`, real `AsyncEmpty` "waiting for signal…" states, and the note-22 consumer logic held unchanged. Stated dependencies (note 25 widgets, note 24 rename) are both satisfied: `widgets/widgets.dart` and `screens/streams_screen.dart`/`StreamsScreen` are present. No missing linkage.
- **Architecture** (`ARCHITECTURE.md`): ✅ No boundary violation. All work is in `example/`; the screen imports only the kit barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`) plus the example-local widget kit — no `lib/src/` reach-through, no `flutter_ppg`/`camera`/`CameraController` types. Guard "Kit `lib/` untouched" (note 27) is honored — the plan touches only the single example screen file.
- **Rules:** No `.ai-factory/RULES.md` present (only `rules/`); no explicit convention file to check. Skill-context file (`.ai-factory/skill-context/aif-review/SKILL.md`) absent — no project overrides to apply.

### Critical Issues

None. Every API the plan names was verified against source:

- `StateBanner(label, color)`, `StatusChip(label, color)`, `SectionCard(title:, child:)`, `AsyncEmpty(message)`, `AsyncError(error)`, `LabelRow(label, value)`, `MetricRow(..., mono:)` — all exported by `widgets/widgets.dart` with the exact signatures the plan uses.
- `qualityColor(quality)`, `goodColor`/`fairColor`/`poorColor`/`idleColor`/`pendingColor` — all present in `status_color.dart`.
- The `AsyncError` name collision is real (`widgets/async_states.dart` defines `AsyncError`; `flutter_riverpod` also exports one). Task 1's instruction to switch to `import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;` is correct and matches the working `source_screen.dart:5` precedent.
- Provider types are right: `rrProvider`/`qualityProvider`/`fingerPresenceProvider`/`stateProvider` are `StreamProvider`s (so `.when` gating in Tasks 3/4 is valid), and `bpmProvider` is a `NotifierProvider<BpmNotifier, int?>` — so `ref.watch(bpmProvider)` yields `int?` and Task 2's `bpm?.toString() ?? '—'` is correct (not an `AsyncValue`).
- `RrInterval.intervalMs` / `.isArtifact` (Task 3) are the fields already used in the current `_rrSection`.
- The "preserve verbatim" set (Task 1) — `_rrHistory`, both `ref.listen` blocks, `ConsumerStatefulWidget`, all provider reads — exactly matches lines 30–53 of the current file, so the note-22 guard is enforceable as written.
- Removing `_stateBanner` in favor of `StateBanner` + a copied `_stateLabelColor` switch is sound: `source_screen.dart:161` is the drop-in source, and the `poorSignal → fairColor` (not `poorColor`) subtlety is preserved by copying that switch verbatim.

### Minor Notes (non-blocking)

- **Task 2 — `MetricRow` alternative is imperfect; prefer the primary `Text` path.** The plan offers "or an equivalent centered `MetricRow` with `mono: true`." `MetricRow` (a) is a left-aligned label+value `Row`, not centered, and (b) formats via `toStringAsFixed(decimals)` with `decimals` defaulting to `3`, so an `int?` BPM would render as `72.000`. The primary suggestion — a centered big `Text(bpm?.toString() ?? '—', ...)` — is the clean path and is what the current code already does; the implementer should take that and treat the `MetricRow` mention as non-authoritative.
- **Task 2 — avoid header duplication.** Placing the card under `SectionCard(title: 'BPM')` while keeping the caption `'BPM (derived, display-only)'` would print "BPM" twice (the same redundancy `source_screen.dart:322` deliberately dodges for the debug panel). The plan already softens the caption to "derived, display-only" — implementer should use a caption without a leading "BPM" to match that intent.

### Positive Notes

- The plan is exceptionally well-grounded: it names a real sibling file (`source_screen.dart`) as the pattern rather than describing an idealized one, and every widget/color/provider it references was verifiable in-tree.
- The import-collision hazard — the single most likely way a naive rebuild would fail to compile — is called out explicitly with the correct fix and a precedent line.
- Scope discipline is strong: presentation-only, single-file, explicit "preserve verbatim" list, explicit no-`done`-arm and kit-`lib/`-untouched guards, all traceable to note 27's Guards.
- Task dependencies (Tasks 2–4 depend on Task 1's scaffold/import switch) are correctly ordered.

PLAN_REVIEW_PASS
