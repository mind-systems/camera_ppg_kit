# Plan Review: CameraPpgSession + streams (05)

**Plan:** `.ai-factory/plans/05-camerappgsession-streams.md`
**Reviewed against:** kit `lib/`, `example/lib/` prior art, `flutter_ppg` 0.2.4 source, notes 07/17/19, ROADMAP Phase 4, ARCHITECTURE.md, rules/base.md
**Risk Level:** 🟡 Medium — the plan is well-scoped and grounded in the proven example, but a few concrete implementation pitfalls and one public-contract divergence should be resolved before coding.

---

## Context Gates

- **Architecture (ARCHITECTURE.md):** ✅ Aligned. The plan honours the load-bearing boundary rule (anti-pattern #48 — no `flutter_ppg`/`camera` type in a public signature): only `RrInterval`, `SignalQuality`, `MeasurementState`, `List<double>`, `CameraPpgError` cross. The debug surface (`debugSignalStream` as `List<double>`) obeys it. Session lives in `src/api/`, matching the module layout. **WARN:** see Finding 1 — the boundary is respected at the type level, but the file will import *two* `SignalQuality` symbols, which is a compile-time hazard the plan does not call out.
- **Rules (rules/base.md):** ✅ Mostly aligned. Errors-as-values (§Error Handling) is respected. **WARN:** §Logging requires plugin logs route through a single internal helper mirroring `neiry_kit/lib/src/util/nlog.dart`; the kit has no `lib/src/util/` helper yet and the plan references "a kit-internal logging helper" inline without scoping its creation (Finding 7).
- **Roadmap (ROADMAP.md):** ✅ Aligned. Maps to Phase 4 "CameraPpgSession + streams" (note 07). Correctly defers camera override to the next milestone (note 08), the acceptance gate to Phase 6 (note 12), and finer state transitions to Phase 5 (note 09). The auto-detect round-trip is legitimately in-scope here per note 07.

---

## Critical Issues

None that block. The plan is implementable and faithfully ports the spike-proven example. The items below are correctness/contract risks to resolve first.

---

## Findings

### 1. (Medium) `SignalQuality` name collision — flutter_ppg exports its own enum
`camera_ppg_session.dart` will `import 'package:flutter_ppg/flutter_ppg.dart'` (for `PPGSignal`, `FlutterPPGService`, `PPGConfig`, `CameraImage` via camera) **and** the kit's own `SignalQuality`. `flutter_ppg`'s barrel re-exports `enum SignalQuality` from `src/models/ppg_signal.dart` (confirmed: `flutter_ppg.dart` → `export 'src/models/ppg_signal.dart'`). Both names are unprefixed and identical, so the file will not compile without disambiguation.
**Fix:** import flutter_ppg with `hide SignalQuality` (the kit derives its own via `SignalQuality.fromSnr(signal.snr)` and does not use `PPGSignal.quality`), or use an import prefix. The plan should state this explicitly in Task 4 so the implementer doesn't discover it as a build break. Note that `PPGSignal` also carries a `quality` field of the *flutter_ppg* enum — the plan correctly ignores it in favour of `fromSnr(snr)`, which sidesteps needing that type.

### 2. (Medium) `start()` return type diverges from the frozen public contract
Tasks 2–3 make `start()` return `Future<CameraPpgError?>`. Note 07 and the freeze (note 19) declare `Future<void> start()`, and note 19 enumerates the frozen surface as `rrStream`/`qualityStream`/`stateStream` with **no error channel** and the guard "keep poorSignal/no-finger as silent-stream + typed state, never an exception." Returning the error as a value is a reasonable resolution of note 07's ambiguity ("surface a typed `CameraPpgError` … and return to idle") and is consistent with ARCHITECTURE anti-pattern #49 (return typed values, don't throw). **But it changes the frozen signature**, and the host currently has no documented way to read a start-time error other than this return value (`MeasurementState` has no `noFinger` member — no-finger returns to `idle`, which the host cannot distinguish from a normal idle without the return value).
**Fix:** keep the `Future<CameraPpgError?>` choice (it's the right one), but the plan should explicitly record that note 07's `Future<void> start()` and the note 19 freeze enumeration must be updated to `Future<CameraPpgError?> start()` when Phase 10 freezes the surface — otherwise the freeze audit will flag a mismatch. Confirm the host UI (`mind_mobile`) can consume a returned error rather than a state, since the freeze contract otherwise promises "state, not exceptions."

### 3. (Medium) Double-start guard idiom does not port from the example
Task 3 says "guard against double-start (no-op if already running)". The example's `MeasurementRunner` implements this as `if (_signalsCtrl != null)` — which works only because it creates its stream controller *per start*. In the kit the four broadcast controllers are created in the constructor and **stay open across stop/start** (Task 1), so `_controller != null`-style or an explicit `bool _running` flag is required; a copied `_xController != null` guard would be permanently true after construction and break `start()` entirely.
**Fix:** specify the guard mechanism (e.g. a dedicated `bool _running` / check `_controller != null`, or gate on `_state != idle`). Also decide the guard's behaviour *during* the async probe round-trip (Task 2 runs ~1.1 s/sensor), so a second `start()` mid-probe is also a no-op.

### 4. (Medium, correctness — already flagged in-plan) RR tail-diff dedup rests on a fragile windowing assumption
`flutter_ppg` recomputes `rrIntervals` **from scratch every frame**: peaks are found over a sliding filtered ring buffer, converted to intervals, then passed through `OutlierFilter.filterOutliersWithStats` (confirmed in `flutter_ppg_service.dart:250-267`). Consequences for `_diffNewIntervals(previous, current)`:
- Values are `seconds * 1000.0` using `effectiveFPS`, which can change (`_resizeBuffersIfNeeded`), so the *same* physical beat can yield a slightly different `double` across frames → equality/tail matching may re-emit it as "new."
- The outlier filter can add/drop entries independently of new peaks, so the list length can change without a genuinely new interval.
- When the ring buffer slides, the front drops while the back grows — a pure "emit the new tail" comparison can misalign.
The plan already acknowledges this ("windowing must be confirmed on-device; Phase-6 gate refines dedup") and correctly designates the pure helper as the one silent-failure surface. **This is acceptable for a minimal passthrough**, but two cautions: (a) the Task 5 unit tests will encode a windowing model that may not match device reality — keep them as tests of the *helper's stated contract*, not proof of correct on-device dedup; (b) prefer matching on interval *identity* by position/anchor if feasible rather than raw `double` equality, to reduce false re-emits. Flag prominently that real dedup lands in Phase 6.

### 5. (Low) `RrInterval.timestamp` semantics vs. what the plan assigns
`RrInterval`'s dartdoc defines `timestamp` as "the later peak — the one that ends this interval." Task 4 assigns `signal.timestamp` (the frame *processing* time) to every interval in a batch. For a minimal passthrough this is a fair approximation, but when a signal carries multiple new intervals they'd all share one frame timestamp, which is not the per-peak time the model documents. Acceptable now; note the deviation so Phase 6 can refine it (peak indices are available on `PPGSignal.peakIndices` if precise peak timing is later wanted).

### 6. (Low) Commit ordering leaves an incoherent intermediate that can strand the torch
Commit 1 (tasks 1–3) introduces `start()` — which opens the controller and sets `FlashMode.torch` — while `stop()`/`_release()` does not arrive until Commit 3 (task 6). Between those commits there is a session that acquires the camera + torch with **no way to release them** — precisely the "torch stuck on / A70 freeze" failure the close-before-cancel invariant exists to prevent. Per repo convention each commit should be independently coherent.
**Fix:** land teardown (task 6) in the same commit as `start()` (Commit 1), or reorder so `stop()`/`_release()` never lags `start()`. The dependency graph allows this since `_release()` only needs the handles established in tasks 1/3, not the conversion logic in task 4.

### 7. (Low) Kit-internal logging helper is referenced but not scoped as a deliverable
Task 1 mentions "a kit-internal logging helper" but lists only `camera_ppg_session.dart` and the barrel in Files. rules/base.md and CLAUDE.md require plugin logs to route through a single internal helper mirroring `neiry_kit/lib/src/util/nlog.dart`; no such helper exists in the kit yet (`lib/src/util/` is absent), and the example's `ppgLog` lives in `example/` and must not be imported by `lib/`.
**Fix:** add `lib/src/util/<nlog>.dart` as an explicit file/step (do not export it from the barrel), and route the session's logs through it.

### 8. (Informational) Locked camera is opened twice — matches the spike, not a defect
Task 2 tears down every probed sensor (including the covered one) before returning, then Task 3 re-opens the locked camera to stream. This mirrors the example (`coverage_detector` → `MeasurementRunner`) and respects "never two controllers open," at the cost of a brief torch off/on between lock and stream. Intentional and correct; noted only so it isn't mistaken for a leak during review of the implementation.

---

## Positive Notes

- **Strong prior-art grounding.** Every hard-won detail from the spike is carried forward: close-before-cancel teardown order, `?.`-guarded frame bridge against late callbacks, best-effort exposure/focus lock in isolated try/catch, `ResolutionPreset.low` + platform `imageFormatGroup`, listen-immediately-skip-by-time probe (avoids the non-broadcast buffering burst).
- **Boundary discipline is explicit and correct** — the "no flutter_ppg/camera type crosses the barrel" rule is stated as load-bearing and the debug surface is kept to `List<double>`.
- **Deferrals are precise and justified** — acceptance config (note 12), camera override (note 08), and finer state transitions (note 09) are each correctly pushed to their own milestones with rationale, keeping this a clean revertable passthrough.
- **Correct identification of the single tested surface** — the pure RR diff helper is the one silent-failure path; camera/stream wiring fails loudly and is verified on-device, matching the project's test philosophy.
- **`SignalQuality.fromSnr` / `CameraPpgError.fromCameraErrorCode` reuse** — the plan leans on the already-built, already-tested model factories rather than re-deriving quality/error mapping at the edge.

---

## Recommendation

Address Findings 1–3 (name collision, `start()` contract divergence, double-start guard mechanism) and 6–7 (commit coherence, logging-helper file) in the plan text before implementation — they are concrete and cheap to pin now. Findings 4–5 are correctly deferred but should stay visible as Phase-6 follow-ups. None are blocking; the plan is fundamentally sound.
