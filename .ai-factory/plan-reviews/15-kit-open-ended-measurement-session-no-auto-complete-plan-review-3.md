# Plan Review 3: Kit — open-ended measurement session (no auto-complete)

**Plan:** `.ai-factory/plans/15-kit-open-ended-measurement-session-no-auto-complete.md`
**Governing spec:** `.ai-factory/notes/23-open-ended-session.md` (via ROADMAP.md:50)
**Files verified:** 11 (kit policy + enum, both tests, 6 example files, plus a full-tree `*.dart` grep for `MeasurementState.done` / `targetDuration` / `setTargetSeconds` / `.isDone` / `_done` / `targetMs`)
**Risk Level:** 🟢 Low

## Verdict

The plan is solid and ready to implement. It cleanly folds in every finding from reviews 1 and 2, and my independent re-verification against live source confirms every file path, line reference, symbol, and consumer it cites. The change set exactly satisfies note 23's target state and its verify grep, and the two-commit split keeps each commit buildable.

Both prior-review defects are resolved:

- **Review-2 finding 1** (`_lastElapsed` orphaned into a write-only field) — fixed. Task 1 now deletes `_lastElapsed` in full (field+doc ~58–59, the `reset()` write ~79, and the trailing `_lastElapsed = elapsed;` ~152), explicitly noting that line 105 is its only reader and that all surviving transitions read absolute `elapsed`, not the marker.
- **Review-2 finding 2** (stale `onSignal` "Per-tick ordering" doc block) — fixed. Task 1 now rewrites lines ~83–96 to the reduced ordering (acceptance → entry-state transition → return state).
- **Review-1 findings 1–4** (two `_start` callers, unused `delta`, `stateProvider:19` doc, `_stateSub = null;` at 99) — all present and cited by exact line.

Only two minor, non-blocking precision notes remain (below). Neither changes the task structure, and both are self-correcting or already covered in spirit — so this review **passes**.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** OK — pure removal within existing kit boundaries (`processing/`, `models/`) plus dead-branch cleanup in the example. No layering, dependency, or module-boundary shift.
- **Roadmap linkage:** OK — ROADMAP.md:50 carries the milestone and names `Spec: .ai-factory/notes/23-open-ended-session.md`. Plan intent (`idle → warmup → measuring ⇄ poorSignal`; 60 s survives only in the calibration countdown, note 21) matches the spec's Key Findings / Target / Verify verbatim. Every consumer note 23 enumerates (`source_screen`, `kit_api_tab`, `stream_providers` bpmProvider, `calibration_recorder`) maps to a task.
- **Rules:** OK — no `.ai-factory/RULES.md`; `rules/base.md` present, no relevant violation. No `skill-context/aif-review/SKILL.md` (absent).
- **Public-surface (spec Guard):** removing `done` from `MeasurementState` is a kit-surface change; note 23 §Guards flags it for the note-19 freeze and confirms it is safe now (`mind_mobile` does not consume the kit until Phase 10). Spec-level bookkeeping, not a plan defect.

## Coverage verification

Full-tree grep over `*.dart` — every live occurrence maps to exactly one task, no stragglers:

| Hit | Task |
|---|---|
| `session_policy.dart:25,38-39,125-126,138,146` | 1 |
| `measurement_state.dart` `done` | 2 |
| `session_policy_test.dart:170-214,216-298` (+ ctor args 173,222) | 3 |
| `models_test.dart:63` | 3 |
| `session_config_provider.dart:45,52-57,69,81` | 4 |
| `stream_providers.dart:61` (+ docs 19, 40-43) | 5 |
| `source_screen.dart:104-111,170,211-213,231,354` | 6 |
| `kit_api_tab.dart:80`, `calibration_screen.dart:237` | 7 |
| `calibration_recorder.dart:31,33-35,58,82-87,39,96-99,144` | 8 |

`auto_detect_screen.dart`'s `_Phase.done` is a distinct local enum, correctly out of scope. `recorder.isDone` has no external caller (only its own definition), so its removal is safe — confirming Task 8's "`save()` is not gated on `isDone`" claim.

## Minor / Optional (non-blocking)

### 1. Task 1 — the `poorSignal` case's inline comment (session_policy.dart:138–139) should be named by line

Task 1's doc-update sentence says to rewrite "the `measuring`/`poorSignal` field doc comments so they no longer describe … target-duration accounting." The only comment this maps to is the **inline comment inside the `poorSignal` `case`** at lines 138–139 (`// poorSignal time does not count toward targetDuration — only time spent in measuring accumulates, via step 2 above`), which references both `targetDuration` and the now-deleted "step 2." Calling it a "field doc comment" is imprecise (it is an inline case comment, and the `measuring` case carries no comment at all), and no explicit line is given. The intent clearly covers it, so an implementer will find and remove it — but citing `session_policy.dart:138-139` would make the edit unambiguous, matching the precision the rest of Task 1 already has.

### 2. Task 1 — `_measured`'s `reset()` line is 78, not 79

Task 1 attributes "its removal from `reset()` (~79)" to `_measured`, then also attributes line 79 to `_lastElapsed`'s reset write. In live source `_measured = Duration.zero;` is at **line 78** and `_lastElapsed = Duration.zero;` at **line 79**. Both lines are deleted anyway (the `~` marks it approximate), so this self-corrects — noted only for accuracy.

## Positive Notes

- **Every prior finding genuinely resolved, not just acknowledged** — the `_lastElapsed` orphan, the `onSignal` doc block, both `_start` call sites, the `delta` local, `stateProvider:19`, and `_stateSub = null;` are each now cited by exact line.
- **Grounded in real code.** Every line number, symbol, and consumer matches current source — including the non-obvious ones (the `_measured`/`enteredMeasuring` entry-state guard, the recorder's dormant `done` listener, the two `_start` callers).
- **Blast radius re-confirmed by grep.** All live `done`/`targetDuration`/`isDone` occurrences map to a task; the lone survivor (`_Phase.done`) is correctly excluded.
- **Correct compile-order reasoning.** Task 2 (enum shrink) gates the four example switch cleanups; the kit-core commit (Tasks 1–3) stays independently buildable and analyzer-clean; the enum-ordinal shift is verified harmless (all consumers use named `switch`/`==`, nothing persists `.index`).
- **Test edits are exact.** The two `session_policy_test.dart` deletions (170–214, 216–298) and the `models_test.dart:63` drop + rename correspond precisely to the removed behavior; warm-up / silence-window / poorSignal⇄measuring coverage is fully preserved.
- **Catches a spec-omitted dependency.** Note 23 lists the recorder's `_done`/listener but not the `targetMs` metadata line (Task 8) — without which Commit 2 would not build; the plan already flags the resulting `schemaVersion: 1` awareness note.

Net: no structural or blocking issues. The two minor notes are precision-only and self-correcting. The plan meets its own analyzer-clean/minimal bar and matches the governing spec.

PLAN_REVIEW_PASS
