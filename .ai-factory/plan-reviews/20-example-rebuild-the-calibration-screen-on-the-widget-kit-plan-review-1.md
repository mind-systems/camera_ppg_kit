# Plan Review: Example — rebuild the Calibration screen on the widget kit

**Plan:** `20-example-rebuild-the-calibration-screen-on-the-widget-kit.md`
**Governing spec:** `.ai-factory/notes/28-calibration-screen-rebuild.md` (via ROADMAP line 55)
**Files verified:** `example/lib/screens/calibration_screen.dart`, `example/lib/screens/streams_screen.dart`, `example/lib/providers/stream_providers.dart`, `example/lib/widgets/*` (widgets barrel, `async_states`, `status_color`, `section_card`, `state_banner`, `status_chip`, `metric_row`)
**Risk Level:** 🟢 Low

## Context Gates

- **Roadmap** — OK. Milestone line 55 (`Example: rebuild the Calibration screen on the widget kit`, still `[ ]`) matches the plan heading; `Spec: notes/28`. Its dependency (note 25 widget kit, line 52) and the assumed note 23 (open-ended session, no `done` arm, line 50) are both `[x]`. No milestone linkage missing.
- **Architecture** — OK. `ARCHITECTURE.md` restricts kit `lib/` and the public barrel; this task is example-app presentation only (`example/lib/screens/`), and the plan explicitly leaves kit `lib/`, the recorder (note 20), and providers untouched. No boundary crossed.
- **Rules** (`.ai-factory/rules/base.md`) — OK. snake_case files, no `pubspec.yaml` hand-edits, no new deps, no proto — none of which this presentation-only change touches. No skill-context file present (`.ai-factory/skill-context/aif-review/` does not exist), so no project overrides apply.

## Critical Issues

None. The plan is technically accurate and implementable. Every API claim was verified against source:

- `hide AsyncError` on the riverpod import correctly resolves the collision with the kit's `AsyncError` in `async_states.dart` — identical to `streams_screen.dart:5`. The calibration screen uses no riverpod `AsyncError`, so hiding it is safe; `AsyncValue`, `Consumer`, `ConsumerState*`, `ref` remain exported.
- Widget constructors are used with the correct positional signatures: `StateBanner(label, color)`, `StatusChip(label, color)`, `AsyncEmpty(message)`, `AsyncError(error)`, `SectionCard(title:, child:)`. All confirmed.
- `qualityColor(SignalQuality?)` from `status_color.dart` and the `loading → AsyncEmpty / error → AsyncError` gating faithfully mirror `streams_screen.dart:_signalCard`.
- `_stateLabelColor` copy over the four enum values (no `done` arm) with `poorSignal → fairColor` matches `streams_screen.dart:85-90` and the note-23 enum. Correct.
- The plan correctly diverges from `streams_screen._bpmCard` on one point and flags it: `_bpmCard` there reads `ref.watch(bpmProvider)` straight from `build()`, but calibration must keep the BPM watch inside its own `Consumer` to preserve the note-21 rebuild-isolation of the 1 Hz countdown. The plan explicitly preserves the `Consumer` and its doc-comment rationale. Good.
- "Presentation only" is respected: `_recorder`, `_finishTimer`/`_tickTimer`, `_finish`/`_stopManually`/`_save`, the `service.isMeasuring` gate, `_blockedByNotMeasuring`, and `dispose` are all left as-is.

## Recommendations (non-blocking)

1. **Make the top `StateBanner` its own `Consumer` explicit (Task 2/4).** The current screen watches `stateProvider` and `qualityProvider` together in the single `_qualityAndStateRow` `Consumer`. The plan splits them into different `ListView` positions — `StateBanner` at the very top, the SQI card lower down — so they can no longer share one `Consumer`. Task 2 says the `qualityProvider`/`stateProvider` watches "must stay off the countdown/buttons," which means the top `StateBanner` needs *its own* `Consumer` wrapping just that banner (watching `stateProvider`), not a `ref.watch(stateProvider)` in `build()`. A naive reading of "at the top of the list" could drop the state watch into `build()` and rebuild the countdown on every state transition — the exact thing note 21's isolation rationale forbids. One sentence spelling out "two Consumers: one for the top banner, one for the SQI card" would remove the ambiguity. (Impact is minor: `stateProvider` emits on lifecycle transitions, not per frame — but it still contradicts the plan's own stated intent.)

2. **Task 2 body under-specifies the finger-presence row.** The task title and the Task 4 ordering both name a "SQI/finger card," and Task 2 says to match `streams_screen.dart:_signalCard` — which renders `LabelRow('Finger', presenceLabel)` from `fingerPresenceProvider` beneath the SQI chip. The Task 2 prose, however, only spells out the SQI `StatusChip`. Since the current calibration screen shows no finger presence at all, this is a small *addition* (benign, consistent with mirroring `_signalCard`, and `fingerPresenceProvider` is already reachable via the existing `stream_providers` import). Worth stating outright that the finger `LabelRow` is included so the implementer doesn't treat it as out-of-scope.

## Positive Notes

- Every cross-file reference the plan makes (`streams_screen.dart:5`, `:_bpmCard`, `:_stateLabelColor`, `:_signalCard`, `status_color.dart`) resolves to the exact construct claimed — the plan was written against the real code, not assumed.
- The plan repeatedly preserves the note-21 isolation doc-comments rather than discarding them during recomposition, and correctly identifies `poorSignal → fairColor` as intentional (guarding against a future "fix" to `poorColor`).
- Task dependencies (1→2→3→4) are ordered so the file compiles at each step, and the final `ListView` reassembly is deferred to Task 4 after all cards exist.
- Scope discipline is strong: kit `lib/`, recorder, timers, and consumer logic are all fenced off; only presentation changes.

PLAN_REVIEW_PASS
