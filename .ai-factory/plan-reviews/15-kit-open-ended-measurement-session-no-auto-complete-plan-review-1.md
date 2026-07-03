# Plan Review: Kit — open-ended measurement session (no auto-complete)

**Plan:** `.ai-factory/plans/15-kit-open-ended-measurement-session-no-auto-complete.md`
**Governing spec:** `.ai-factory/notes/23-open-ended-session.md` (via ROADMAP.md:50)
**Files verified:** 9 (kit policy + enum, both tests, 5 example files, production session/service)
**Risk Level:** 🟢 Low

## Verdict

The plan is solid, accurate, and well-scoped. Every file path, line reference, and consumer it cites was verified against the live code and matches. Task ordering and dependencies are correct, the commit split is sound, and the change set exactly satisfies note 23's target state and verify grep (`MeasurementState.done|targetDuration` → no hits). It even catches a compile dependency note 23 omits (the `targetMs` metadata line in `calibration_recorder.save()`, Task 8).

Findings below are minor precision/completeness gaps — none architectural, none blocking. They are worth fixing so the result stays analyzer-clean and no call site momentarily breaks.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** WARN — none. Change is a pure removal within existing kit boundaries (policy/models) plus dead-branch cleanup in the example; no dependency or layering shift.
- **Roadmap linkage:** OK — ROADMAP.md:50 carries the milestone and names `Spec: .ai-factory/notes/23-open-ended-session.md`. Plan intent (open-ended `idle → warmup → measuring ⇄ poorSignal`, 60 s lives only in the calibration countdown) matches the spec's Key Findings/Target/Guards.
- **Rules:** OK — no `RULES.md` at `.ai-factory/` root; `rules/base.md` present, no relevant violation. No `skill-context/aif-review/SKILL.md` (absent).
- **Public-surface note (spec Guard):** the plan removes `done` from the `MeasurementState` enum. Note 23 §Guards flags this for the note-19 freeze and confirms it is safe now (`mind_mobile` does not yet consume the kit). The plan does not restate this, but it is a spec-level bookkeeping item, not a plan defect.

## Issues

### 1. Task 6 — `_start` has two callers, not "single" (wrong-assumption)
The plan says: *"If `_start`'s `currentState` parameter becomes unused after the edit, drop it and update its single caller."* After the `done`-recovery block is removed, `currentState` **is** unused, so it will be dropped — but `_start` is called at **two** sites:
- `source_screen.dart:231` — `onPressed: isRunning ? null : () => _start(state)` (Start button)
- `source_screen.dart:213` — `_start(MeasurementState.idle)` (retry banner)

Both must change to `_start()`. Following "its single caller" literally leaves the other call passing an argument to a now-zero-arg method → Dart arg-count compile error. The breakage is loud (won't build), so it self-corrects, but the instruction is misleading. Additionally, the retry-banner comment at `source_screen.dart:211–212` ("A failed start() always leaves the session at `idle` … retry never needs the `done`-recovery path") becomes stale once `done` is gone and should be removed as part of this task.

### 2. Task 1 — leftover unused `delta` local (completeness)
The plan removes `_measured`, the `enteredMeasuring` declaration, and the `if (enteredMeasuring) _measured += delta;` block (cited "~106-109"). But `final delta = elapsed - _lastElapsed;` at **line 105** is *not* in that range, and `delta`'s only use is `_measured += delta`. Once `_measured` is gone, `delta` becomes an unused local (`unused_local_variable`). This won't fail `flutter test`, but it surfaces in `flutter analyze` and contradicts the "minimal/clean" intent. Task 1 should also delete line 105 (`final delta = ...`) — after which lines 105–109 are removed as one contiguous block, leaving `onSignal` computing no per-tick delta at all (correct: nothing needs it anymore; `_lastElapsed = elapsed` at the end stays).

### 3. Task 5 — stale `done` doc reference at `stream_providers.dart:19` (completeness)
Task 5 updates only the `BpmNotifier` doc (~40-43). But the `stateProvider` doc comment at **line 19** also reads *"never reimplement the warm-up/measuring/poorSignal/done state machine"*. That `done` mention is left behind. Not a compile issue, but a lingering reference to a removed state; drop `/done` there too for consistency with the four-value enum.

### 4. Task 8 — `_stateSub = null;` at line 99 not called out (precision)
Task 8 says to remove `_stateSub?.cancel()` in `stop()`. `stop()` also has `_stateSub = null;` at **line 99**, which must go with the field. Removing the field declaration forces this (else compile error), so it self-corrects — but the plan should name it so the edit to `stop()` is unambiguous. (`dart:async` import stays — `_rrSub`/`_qualitySub` remain `StreamSubscription`.)

## Minor / Optional

- **Calibration export schema:** Task 8 drops `'targetMs'` from the exported run metadata (correct — `policy.targetDuration` no longer exists) but the JSON `schemaVersion` stays `1`. If any calibration-analysis tooling keys on `policy.targetMs`, it will now see it absent under the same version. This is a dev-only artifact (note 20) and acceptable, but worth a one-line awareness note. Low priority.

## Positive Notes

- **Grounded in the real code.** Every line number, symbol, and consumer the plan cites matches the current source — including the non-obvious ones (the `_measured` accumulator semantics, the `enteredMeasuring` entry-state guard, the recorder's dormant `done` listener).
- **Correct blast-radius analysis.** Confirmed the production session (`lib/src/api/camera_ppg_session.dart` `_onSignal`/`_setState`) and the example service never branch on `done` and hold no exhaustive `switch` over `MeasurementState` — so the enum shrink ripples only to the four example switches the plan already enumerates. `auto_detect_screen.dart:90`'s `_Phase.done` is a distinct local enum and correctly left untouched.
- **Catches a compile dependency the spec omits.** Note 23 lists the recorder's `_done`/`isDone`/listener but not the `targetMs` metadata line; Task 8 removes it, without which Commit 2 would not build.
- **Dependencies and commit split are right.** Task 2 (enum) gates the example cleanups; the two-commit boundary (kit core, then example) keeps each commit self-consistent and buildable.
- **Test updates are exact.** The `models_test` four-value assertion and the two `session_policy_test` deletions correspond precisely to the removed behavior; remaining warm-up/silence/poorSignal coverage is preserved.

Net: address finding 1 (wrong caller count — most likely to trip the implementer) and fold in findings 2–4 for an analyzer-clean result. No structural changes needed.
