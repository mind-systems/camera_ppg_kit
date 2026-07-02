# Plan Review 2: CameraPpgSession + streams (05)

**Plan:** `.ai-factory/plans/05-camerappgsession-streams.md`
**Reviewed against:** kit `lib/` (models + barrel), `example/lib/` prior art (`measurement_runner.dart`, `coverage_detector.dart`, `camera_probe.dart`, `common/finger_presence.dart`), `flutter_ppg` 0.2.4 (`ppg_signal.dart`, `flutter_ppg_service.dart`), notes 07/12/19, ARCHITECTURE.md, ROADMAP Phase 4
**Round:** 2 (review 1 raised F1–F8; this pass verifies their incorporation and re-checks the codebase)
**Risk Level:** 🟡 Medium — review 1's eight findings are all faithfully incorporated, but tracing the new `_running` guard (F3) across `start()`'s early-return paths exposes one concrete correctness gap that would break the retry-after-no-finger path. One line of plan text fixes it.

---

## Context Gates

- **Architecture (ARCHITECTURE.md):** ✅ Aligned. The load-bearing boundary rule is honoured — only `RrInterval`, `SignalQuality`, `MeasurementState`, `List<double>`, `CameraPpgError` cross; `debugSignalStream` stays `List<double>`; session lives in `src/api/`; logging routes through a new `src/util/` helper (not exported). Two **WARN**s below (nothing blocking):
  - The plan cites "ARCHITECTURE anti-pattern #48 / #49." ARCHITECTURE.md lists its anti-patterns as unnumbered bullets — there is no #48/#49. The *concepts* are real (no `flutter_ppg`/`camera` type in a public signature → line 114; return typed values, don't throw → lines 49/116), so this is a traceability/cosmetic mismatch, not a substantive error. Consider dropping the invented numbers or pointing at the bullet text.
  - ARCHITECTURE line 116 says no-finger should be surfaced by "emitting a typed state." The plan's F2 resolution returns `CameraPpgError.noFinger` as a value instead (because `MeasurementState` has no `noFinger` member). This is defensible and does not throw, but the plan only schedules notes 07/19 for reconciliation at freeze — ARCHITECTURE's "emit a typed state" wording deserves the same reconciliation note so the freeze audit doesn't read it as a third mismatch.
- **Rules (rules/base.md):** ✅ Aligned. Errors-as-values respected; F7's dedicated `lib/src/util/nlog.dart` deliverable satisfies the single-internal-logger requirement and the "never import example's `ppgLog`" constraint. (No `.ai-factory/RULES.md` exists; `rules/` dir is the source — consistent with prior reviews.)
- **Roadmap (ROADMAP.md):** ✅ Aligned. Maps cleanly to Phase 4 "CameraPpgSession + streams" (note 07). Deferrals are correct: camera override → note 08, acceptance gate → note 12, finer state transitions → note 09, per-peak timestamps → Phase 6. The close-before-cancel teardown invariant (ROADMAP line 17) is carried forward verbatim.
- **Skill-context:** none present (`.ai-factory/skill-context/` absent) — no project-specific overrides to apply.

---

## Incorporation of Review-1 Findings (all confirmed present)

| # | Review-1 finding | Status in plan |
|---|---|---|
| F1 | `SignalQuality` name collision | ✅ `import ... hide SignalQuality` mandated in Assumptions + Tasks 3/6; verified `flutter_ppg/.../ppg_signal.dart` does export its own `enum SignalQuality`, and the kit uses `fromSnr(signal.snr)`, never `PPGSignal.quality`. |
| F2 | `start()` returns `Future<CameraPpgError?>` diverges from freeze | ✅ Documented as deliberate; notes 07/19 flagged for freeze update. (See ARCHITECTURE WARN above for the one loose end.) |
| F3 | Double-start guard idiom doesn't port | ✅ Task 4 mandates a `bool _running` flag, explicitly warns the example's `_xController != null` idiom is permanently-true here. **But see Finding 1 — the clear-path is under-specified.** |
| F4 | Fragile RR tail-diff | ✅ Called out in Task 6 + Task 7 with the Phase-6 follow-up; tests scoped to the helper's stated contract. |
| F5 | `RrInterval.timestamp` vs frame time | ✅ Noted as deviation; `peakIndices` cited for Phase 6. Verified `PPGSignal.timestamp` and `RrInterval.timestamp` are both `DateTime` — the assignment type-checks. |
| F6 | Commit ordering strands the torch | ✅ Fixed — `stop()`/`_release()` now lands in Commit 1 alongside `start()`. |
| F7 | Logging helper not scoped | ✅ Now Task 1 with explicit `lib/src/util/nlog.dart`, not barrel-exported. |
| F8 | Locked camera opened twice | ✅ Carried as informational in Task 3. |

The port descriptions match the example sources: teardown order in Task 5 mirrors `_tearDown` in `coverage_detector.dart` exactly; the `?.`-guarded frame bridge, `ResolutionPreset.low` + platform `imageFormatGroup`, best-effort exposure/focus lock, and the listen-immediately-skip-by-time probe are all faithful. `PPGSignal.rrIntervals` being ms-valued `double` matches `RrInterval(intervalMs: rr.round())`. `service.dispose()` (unawaited `void`) matches the package signature.

---

## Critical Issues

None that hard-block. The item below is a concrete correctness gap, cheap to pin in the plan text, and would otherwise surface as a runtime dead-lock on the most common error path.

---

## Findings

### 1. (Medium, correctness) `_running` is never cleared on `start()`'s early-return failure paths — retry-after-no-finger becomes a permanent no-op

Task 4 sets `_running = true` "at the very top of `start()` (before the async probe)" and states `_running` "is cleared in `_release()`." But `start()` has **three** exit paths, and only one of them reaches `_release()`:

1. **Probe finds a covered sensor** → open controller → `measuring`. (`_running` stays true — correct.)
2. **Task 4 camera-setup throws** → "on failure run `_release()`" → `_running` cleared. (Correct.)
3. **Probe returns `CameraPpgError.noFinger`, or a probe `CameraException` maps via `fromCameraErrorCode`** (both in Task 3) → `start()` returns the error **before** Task 4's camera-setup block ever runs.

Path 3 is not described as calling `_release()` or otherwise clearing `_running`. Because `_running` was set true at the top, after the first no-finger result the session is stuck: every subsequent `start()` hits the double-start guard and returns immediately as a no-op. This defeats the entire purpose of returning a *retryable* typed error (F2) — no-finger is the expected "reposition your finger and press Start again" outcome, and the retry would silently never fire.

Note the probe helper (Task 3) tears down its *own* per-probe controllers internally, so on path 3 no persistent handle is open — calling `_release()` there is cheap (handles are null) and its only real effect is clearing `_running` and resetting state to `idle`, which is exactly what's needed.

**Fix:** state in Task 3/Task 4 that **every** early-return from `start()` (no-finger, probe `CameraException`, and any pre-lock failure) must clear `_running` and set state `idle` before returning — e.g. route all failure returns through `_release()`, or wrap the whole of `start()` (probe + setup) in a single try/finally that clears `_running` unless a lock succeeded. Pick one mechanism and name it, so the implementer doesn't leave path 3 dangling.

### 2. (Low, cross-reference) Task 4 points at the wrong task for `_release()`

Task 4 says "`_running` is cleared in `_release()` (Task 7)." `_release()` is defined in **Task 5**; Task 7 is the RR-diff unit test. Fix the pointer (compounds with Finding 1 — the reader chasing where `_running` is cleared lands on the test file).

### 3. (Low, cosmetic) Duplicated Assumptions bullet

The "`RrAcceptanceConfig? acceptance` ctor input … is deferred" bullet appears twice, verbatim (lines 15 and 16). Delete one.

---

## Positive Notes

- **Every review-1 finding is genuinely addressed, not hand-waved** — F3 in particular introduces the correct `_running` mechanism and explicitly warns against the copy-paste `!= null` trap; the only gap is tracing that flag through path 3 (Finding 1), which is a natural next step from the fix it already made.
- **Faithful to the spike.** Close-before-cancel teardown, the `?.`-guarded bridge, listen-immediately-skip-by-time probe, and platform `imageFormatGroup` are all carried over exactly as the on-device A70 work proved them.
- **Boundary discipline verified at the source level** — confirmed `flutter_ppg` re-exports a colliding `SignalQuality` and that the kit's `fromSnr(snr)` path sidesteps `PPGSignal.quality`, so `hide SignalQuality` is both necessary and sufficient.
- **Correct single tested surface.** The pure `_diffNewIntervals` helper is the one silent-failure path; camera/stream wiring fails loudly and is verified on-device — matches the project's test philosophy, and the tests are honestly scoped to the helper's contract rather than claiming to prove device dedup.
- **Deferrals stay visible** as an explicit Phase-6 follow-up list, keeping this a clean revertable passthrough.

---

## Recommendation

Pin **Finding 1** (clear `_running` on all `start()` failure returns) and fix the two low items (**2, 3**) in the plan text before implementation. Finding 1 is the only one with runtime consequences — left as-is it would ship a session that no-ops after the first missed finger. The rest of the plan is sound and faithfully incorporates round 1. Not blocking beyond that one line of pinning.
