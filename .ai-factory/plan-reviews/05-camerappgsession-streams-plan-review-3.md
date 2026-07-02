# Plan Review 3: CameraPpgSession + streams (05)

**Plan:** `.ai-factory/plans/05-camerappgsession-streams.md`
**Reviewed against:** kit `lib/` (models + barrel), `example/lib/` prior art (`measurement_runner.dart`, `coverage_detector.dart`, `camera_probe.dart`, `common/finger_presence.dart`), `flutter_ppg` 0.2.4 source (`ppg_signal.dart`, `flutter_ppg_service.dart`, `flutter_ppg.dart`), ARCHITECTURE.md, prior reviews 1 & 2
**Round:** 3 (verifies incorporation of review-1 F1–F8 and review-2 F1–F3, and re-checks every technical claim against source)
**Risk Level:** 🟢 Low — every finding from rounds 1 and 2 is faithfully incorporated, and each technical assertion in the plan was re-verified against the actual `flutter_ppg` source and example code. No blocking or correctness issues remain.

---

## Code Review Summary

**Files Reviewed:** plan (1) + 11 supporting source files (kit models, barrel, 3 example ports, 3 flutter_ppg source files, ARCHITECTURE.md)
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture (ARCHITECTURE.md):** ✅ Aligned. The load-bearing boundary rule (no `flutter_ppg`/`camera` type in a public signature — ARCHITECTURE.md line 114/anti-pattern bullets) is honoured: only `RrInterval`, `SignalQuality`, `MeasurementState`, `List<double>`, `CameraPpgError` cross the barrel; internal handles (`CameraController`, `PPGSignal`, `FlutterPPGService`, `StreamController<CameraImage>`) stay as private fields. `debugSignalStream` is `List<double>`. Session lives in `src/api/`; logging routes through a new, non-exported `src/util/nlog.dart`. The round-2 WARN about invented anti-pattern numbers (`#48/#49`) is resolved — the plan now cites concrete line numbers (114, 49/116). The round-2 WARN about ARCHITECTURE line 116's "emit a typed state" wording is addressed: the plan explicitly schedules line 116 for reconciliation at the Phase-10 freeze alongside notes 07/19 (plan line 14).
- **Rules (rules/base.md):** ✅ Aligned. Errors-as-values respected (verified against `CameraPpgError.fromCameraErrorCode`, which returns typed values and never throws). The single-internal-logger requirement is satisfied by Task 1's dedicated `lib/src/util/nlog.dart`, and the "never import example's `ppgLog`" constraint is stated. No `.ai-factory/RULES.md` exists; `rules/` is the source — consistent with prior rounds.
- **Roadmap (ROADMAP.md):** ✅ Aligned. Maps to Phase 4 "CameraPpgSession + streams" (note 07). Deferrals are precise: camera override → note 08, acceptance gate → note 12, finer state transitions → note 09, per-peak timestamps → Phase 6. The close-before-cancel teardown invariant is carried forward verbatim.
- **Skill-context:** none present (`.ai-factory/skill-context/aif-review/SKILL.md` absent) — no project-specific overrides to apply.

### Critical Issues

None. The plan is implementable as written and faithfully ports the spike-proven example.

---

## Incorporation of prior findings (all confirmed, source-verified)

| # | Finding (round) | Status |
|---|---|---|
| R1-F1 | `SignalQuality` name collision | ✅ **Verified at source.** `flutter_ppg/lib/src/models/ppg_signal.dart:2` declares `enum SignalQuality`, and `flutter_ppg.dart:36` re-exports it. The plan mandates `import ... hide SignalQuality` in Assumptions + Tasks 3/6 and derives quality via `SignalQuality.fromSnr(signal.snr)` — `snr` is a real `double` field (`ppg_signal.dart:46`). `hide` is necessary and sufficient. |
| R1-F2 | `start()` return-type divergence | ✅ Documented as deliberate; notes 07/19 **and** ARCHITECTURE line 116 flagged for freeze reconciliation (plan line 14). `MeasurementState` (verified) has no `noFinger`/error member, so a return value is the only way to surface a retryable no-finger — the choice is sound. |
| R1-F3 | Double-start guard idiom | ✅ `bool _running` mandated; the example's `_xController != null` trap is explicitly called out as permanently-true here (broadcast controllers created once in ctor). |
| R1-F4 | Fragile RR tail-diff | ✅ **Verified at source.** `flutter_ppg_service.dart:263-267` recomputes `rrIntervals` from scratch each frame (`peaksToRRIntervals(effectiveFPS)` → `filterOutliersWithStats`), confirming the tail-diff fragility. Called out in Task 6/7 with the Phase-6 follow-up; tests scoped to the helper's stated contract. |
| R1-F5 | `RrInterval.timestamp` vs frame time | ✅ Noted as a deviation; `peakIndices` cited for Phase 6. Verified `PPGSignal.timestamp` (`ppg_signal.dart:39`) and `RrInterval.timestamp` are both `DateTime` — the assignment type-checks. |
| R1-F6 | Commit ordering strands the torch | ✅ `stop()`/`_release()` lands in Commit 1 with `start()` (Commit Plan + Task 5). |
| R1-F7 | Logging helper not scoped | ✅ Task 1 delivers `lib/src/util/nlog.dart`, not barrel-exported. |
| R1-F8 | Locked camera opened twice | ✅ Carried as informational in Task 3. |
| R2-F1 | `_running` never cleared on early-return failure paths | ✅ **Fixed.** Task 3 requires every early return (no-finger, probe `CameraException`) to clear `_running` and reset to `idle`; Task 4 enumerates all three exits and mandates a single mechanism (try/finally clearing `_running` unless a lock succeeded, or routing all failures through `_release()`). The retry-after-no-finger dead-lock is closed. |
| R2-F2 | Wrong task pointer for `_release()` | ✅ Fixed — Task 4 now attributes `_release()` to Task 5. |
| R2-F3 | Duplicated Assumptions bullet | ✅ Fixed — the `RrAcceptanceConfig? acceptance` bullet now appears once (plan line 15). |

### Source-level re-verification of the port

- **Teardown order** (Task 5) matches `_tearDown` in `coverage_detector.dart:178-217` and `MeasurementRunner.stop` exactly: stopImageStream → close bridge **before** cancel → cancel sub → `service.dispose()` → torch off → controller.dispose. Confirmed `processImageStream` is `async*` (`flutter_ppg_service.dart:155`), so the close-before-cancel invariant is real, and `dispose()` is `void` (line 113), matching the unawaited call.
- **Frame bridge** `?.`-guard, `ResolutionPreset.low`, platform `imageFormatGroup` (iOS bgra8888 / else yuv420), best-effort exposure/focus lock in isolated try/catch — all faithful to `measurement_runner.dart:56-138`.
- **Probe round-trip** (Task 3): rear-camera enumeration filtered to `CameraLensDirection.back` in `availableCameras()` order (matches `camera_probe.dart:34-44`), listen-immediately-skip-by-time, finger-presence bounds `raw > fingerPresenceMin && raw < fingerPresenceMax` (matches `finger_presence.dart:11-16`), coverage threshold ≥ 0.6, sequential teardown-before-next (matches `coverage_detector.dart:36-163`).
- **Conversion** (Task 6): `PPGSignal.rrIntervals` is a `List<double>` of milliseconds (`ppg_signal.dart:30-33`) → `RrInterval(intervalMs: rr.round())` is correct; `snr`, `rawIntensity`, `filteredIntensity`, `peakIndices` all exist as claimed.

### Positive Notes

- **Every prior-round finding is genuinely resolved, not hand-waved** — the round-2 correctness gap (F1) that would have made the session a permanent no-op after the first missed finger is closed with a single, explicitly-named mechanism.
- **Boundary discipline verified at the source level** — the `SignalQuality` collision, the ms-valued `rrIntervals`, the `async*` teardown deadlock, and the recompute-every-frame RR behavior were all confirmed against `flutter_ppg` 0.2.4, so the plan's design rationale rests on the real API, not assumption.
- **Correct single tested surface** — the pure `_diffNewIntervals` helper is the one silent-failure path; camera/stream wiring fails loudly and is verified on-device, matching the project's test philosophy, with tests honestly scoped to the helper's contract rather than claiming device dedup.
- **Deferrals stay visible** as an explicit Phase-6 follow-up list, keeping this a clean, revertable passthrough.

---

## Recommendation

The plan is solid. All eleven findings from rounds 1 and 2 are incorporated, and every technical claim was re-verified against the actual `flutter_ppg` source and example code. There are no blocking, correctness, or architectural issues remaining. Proceed to implementation.

PLAN_REVIEW_PASS
