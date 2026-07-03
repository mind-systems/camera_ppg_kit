## Code Review Summary

**Files Reviewed:** 1 plan (`27-preview-square-in-the-signal-card-reset-on-stop.md`) against `source_screen.dart`, `source_lifecycle.dart`, `stream_providers.dart`, `camera_ppg_session.dart`, `async_states.dart`, spec note 37, ROADMAP line 72.
**Risk Level:** 🟢 Low

### Context Gates
- **Roadmap** (WARN/none): The plan's title matches ROADMAP.md line 72 ("Preview square in the Signal card + reset on Stop") exactly, and its `Spec:` reference (`notes/37-preview-in-signal-card.md`) exists and is faithfully followed. Linkage is intact. This kit is intentionally outside root orchestration (planning stays local) per the kit's CLAUDE.md — no cross-repo gate applies.
- **Architecture / Rules**: No `.ai-factory/skill-context/aif-review/SKILL.md` present. `.ai-factory/rules/base.md` and `ARCHITECTURE.md` exist but contain no convention that this example-only UI change violates. No boundary issues: the change stays in `example/lib/`, touches no kit `lib/` surface, adds no proto (correct — this kit has none).

### Critical Issues
None. Every load-bearing claim in the plan was verified against the code:

- `CameraPpgSession.buildPreview()` exists and returns `Widget?`, non-null only between lock and teardown (`camera_ppg_session.dart:193`) — the plan's "fresh read each build → placeholder after Stop" reasoning holds, because `stopMeasurement()` nulls the service session and `_controller` (confirmed by the existing `_cameraOverrideCard` doc-comment at lines 310–317).
- The `session?.buildPreview()` read path (`ref.read(cameraPpgServiceProvider).session?.buildPreview()`) is already used verbatim in the current `_previewCard()` (line 244) — the plan reuses a proven call, not an invented API.
- `lifecycleProvider` yields `SourceLifecycle`; `isActive` = `warmup`/`measuring`/`poorSignal`, so `!isActive` = `idle`/`starting`/`stopping` exactly as the plan states (`source_lifecycle.dart:34–37`). `build()` already computes `lifecycle` via `ref.watch(lifecycleProvider)` (line 125), so passing it into `_signalCard(lifecycle)` needs no new wiring and the whole screen already rebuilds on lifecycle change — the rebuild driver the fresh `buildPreview()` read depends on is present.
- `AsyncEmpty` (placeholder) exists in `async_states.dart`; `StatusChip`/`LabelRow`/`qualityColor` are already used in `_signalCard`.
- The deletion targets are correct: `_previewCard()` is defined at 243–257 and invoked only at `build()` lines 140–141 (`_previewCard(), const SizedBox(height: 16),`); no other reference exists.
- The described bug is real: `qualityProvider` is a `StreamProvider` over a long-lived stream, so it retains its last `AsyncData` after Stop and never reverts to `loading` — lifecycle gating is the right fix.
- The layout is structurally sound: `AspectRatio(1)` inside `Expanded` inside a `Row` inside the `ListView`-hosted `Column` resolves cleanly (Expanded supplies a tight finite width, AspectRatio derives finite height from it, so the Row gets a bounded cross-axis height and the sibling `Center`/`AsyncEmpty` aligns within it — no unbounded-constraint crash).

### Minor Notes (non-blocking)
- **Square size vs. stated intent.** Two `Expanded` (flex 1 each) makes the preview square ≈ half the card width, which is larger than the "roughly SQI-chip width / small square" phrasing suggests (the SQI `StatusChip` is much narrower than half the card). This is a cosmetic outcome, not a defect — the plan itself hedges with "roughly SQI-chip width each." If a genuinely small square is wanted, the implementer may need a fixed-width right side (e.g. `SizedBox(width: ~72)`) rather than a 1:1 `Expanded` split. Flagging only so the implementer doesn't treat "half-width" as a mistake to fix later.
- **Redundant-but-safe preview gating.** In Task 2 the preview already reverts to its placeholder naturally when not active (session/`_controller` null → `buildPreview()` returns null), so the explicit `!isActive` branch for the preview is belt-and-suspenders. This matches note 37's "gate the preview on lifecycle" instruction and is harmless — no change needed, just noting the SQI chip is the branch that strictly requires the gate.

### Positive Notes
- The plan correctly scopes to example-only, explicitly forbids touching kit `lib/` and reintroducing a `done` arm (notes 35/23), matching the surrounding code's own guard comments.
- Task ordering (recompose first, then lifecycle-gate with an explicit `depends on Task 1`) is right, and the call-site change (`_signalCard(lifecycle)`) is spelled out.
- File paths, method names, provider names, and widget names are all accurate — no fabricated API surface.
- Faithful to spec note 37 and ROADMAP line 72 with no drift.

PLAN_REVIEW_PASS
