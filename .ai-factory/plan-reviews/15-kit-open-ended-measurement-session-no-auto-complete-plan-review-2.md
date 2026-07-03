# Plan Review 2: Kit — open-ended measurement session (no auto-complete)

**Plan:** `.ai-factory/plans/15-kit-open-ended-measurement-session-no-auto-complete.md`
**Governing spec:** `.ai-factory/notes/23-open-ended-session.md` (via ROADMAP.md:50)
**Files verified:** 11 (kit policy + enum, both tests, 6 example files, plus a full-tree grep for `done`/`targetDuration`)
**Risk Level:** 🟢 Low

## Verdict

The plan is well-grounded and now cleanly folds in every finding from review-1:

- **Finding 1** (Task 6 — two `_start` callers) — fixed. The plan now names both `source_screen.dart:231` and `:213`, drops the `currentState` param to `_start()`, and deletes the stale retry-banner comment at 211–212.
- **Finding 2** (Task 1 — unused `delta`) — fixed. Line 105 (`final delta = …`) is now explicitly inside the removed 105–109 block.
- **Finding 3** (Task 5 — `stateProvider:19` doc) — fixed. The plan now edits the line-19 comment too.
- **Finding 4** (Task 8 — `_stateSub = null;` at 99) — fixed. Called out by line.
- **Minor** (schema version awareness) — folded into Task 8.

Every file path, line reference, and consumer the plan cites was re-verified against the live source and matches. The full-tree grep confirms the eight tasks cover *all* live occurrences of `MeasurementState.done` / `targetDuration` / `setTargetSeconds` / `_done` / `isDone`; the only untouched hit is `auto_detect_screen.dart:90`'s `_Phase.done`, a distinct local enum correctly left alone.

However, my independent re-analysis of Task 1 surfaces one **chained dead-code defect** that both the plan and review-1 missed. It is the mirror of review-1's finding 2, one level deeper, and it contradicts an explicit instruction in the plan. It should be fixed before implementation, so this review does **not** pass.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** WARN — none. Pure removal within existing kit boundaries (`processing/`, `models/`) plus dead-branch cleanup in the example. No layering or dependency shift.
- **Roadmap linkage:** OK — ROADMAP.md:50 carries the milestone and names `Spec: .ai-factory/notes/23-open-ended-session.md`. Plan intent (open-ended `idle → warmup → measuring ⇄ poorSignal`; 60 s survives only in the calibration countdown) matches the spec.
- **Rules:** OK — no `.ai-factory/RULES.md`; `rules/base.md` present, no relevant violation. No `skill-context/aif-review/SKILL.md`.
- **Public-surface note (spec Guard):** removing `done` from the `MeasurementState` enum is flagged safe by note 23 §Guards (`mind_mobile` does not yet consume the kit). Spec-level bookkeeping, not a plan defect.

## Critical Issues

### 1. Task 1 — removing `delta` orphans `_lastElapsed` into a write-only dead field (wrong-assumption)

The plan states, verbatim:

> after removal `onSignal` computes no per-tick delta at all (nothing needs it; **the `_lastElapsed = elapsed` update at the end of `onSignal` stays**)

This is incorrect. `_lastElapsed` has exactly **one reader** in the whole file — line 105, `final delta = elapsed - _lastElapsed;` — which Task 1 removes. Its only remaining touch points are two *writes*:

- `session_policy.dart:79` — `_lastElapsed = Duration.zero;` (in `reset()`)
- `session_policy.dart:152` — `_lastElapsed = elapsed;` (end of `onSignal`)

Once the sole reader is gone, `_lastElapsed` becomes an assigned-but-never-read private field, which the Dart analyzer flags as **`unused_field`** ("The value of the field '_lastElapsed' isn't used."). This is the exact class of leftover review-1's finding 2 set out to avoid — the plan fixed the `delta` local but, by keeping its downstream `_lastElapsed`, reintroduced the same analyzer warning one level up. It defeats the plan's own "analyzer-clean / minimal" intent (and would fail any `flutter analyze` gate that treats warnings as errors).

**Fix:** Task 1 must also delete `_lastElapsed` entirely — its declaration + doc (lines 58–59), the `_lastElapsed = Duration.zero;` line in `reset()` (79), and the trailing `_lastElapsed = elapsed;` (152) — *not* keep the trailing assignment as the plan currently instructs. After this, `onSignal` holds no delta/last-elapsed bookkeeping at all: it computes `accepted`, runs the `switch`, and returns `_state`. Confirmed none of the surviving transitions (`warmup → measuring` on absolute `elapsed >= warmupDuration`; `measuring → poorSignal` via `_badSince` + absolute `elapsed`; `poorSignal → measuring` on `accepted`) reads `_lastElapsed`, so nothing else depends on it.

## Issues

### 2. Task 1 — `onSignal`'s "Per-tick ordering" doc block (lines 83–96) left stale (completeness)

Task 1 says to update "the class doc comment (lines 4-21) and the `measuring`/`poorSignal` doc comments," but does not mention the **method-level doc on `onSignal` (lines 83–96)**. That block enumerates a "Per-tick ordering" whose steps describe precisely the machinery being deleted:

- Step 1 — *"Compute `delta = elapsed - lastElapsed`."*
- Step 2 — *"Add `delta` to the measured-time accumulator, but only if the state at tick entry was already `measuring`…"*
- Step 4 — *"Unconditionally update the last-elapsed marker… so the next tick's `delta` stays small."*

With finding 1 applied (delta, `_measured`, and `_lastElapsed` all gone), steps 1, 2, and 4 describe code that no longer exists. Task 1 should rewrite this block to the reduced ordering (evaluate acceptance → run the entry-state transition → return state). Doc-only, non-blocking, but it is the most load-bearing comment in the file and should not be left describing removed behavior.

## Minor / Optional

- **Calibration export schema (Task 8):** dropping `'targetMs'` while leaving `schemaVersion: 1` is acceptable for this dev-only artifact (note 20); the plan already flags it. No change requested.
- **Enum ordinal shift:** removing `done` (index 3 of 5) shifts `poorSignal` from index 4 → 3. Verified nothing persists or compares `MeasurementState.index`/ordinal — all consumers use named `switch`/`==`. No action needed; noted for completeness.

## Positive Notes

- **Every review-1 finding genuinely resolved**, not just acknowledged — the two `_start` call sites, the `delta` line, the `stateProvider:19` doc, and `_stateSub = null;` are each now cited by exact line.
- **Blast radius re-confirmed by grep.** All live `done`/`targetDuration` occurrences map to a task; the lone survivor (`_Phase.done` in `auto_detect_screen.dart`) is correctly out of scope.
- **Test edits are exact.** `models_test.dart:63` drop + rename to "four expected lifecycle values," and the two targeted `session_policy_test.dart` deletions (170–214, 216–298) correspond precisely to the removed behavior; warm-up/silence/poorSignal coverage is preserved.
- **Dependency graph and two-commit split are sound** — enum shrink (Task 2) gates the example cleanups; kit-core commit stays independently buildable.

Net: one real fix required (finding 1 — remove `_lastElapsed`, do not keep its trailing write) to hit the plan's own analyzer-clean bar, plus finding 2 folded in for doc consistency. No structural changes.
