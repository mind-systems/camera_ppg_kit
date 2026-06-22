# Plan Review: Signal-based camera auto-detect (round 2)

**Plan:** `.ai-factory/plans/01-signal-based-camera-auto-detect.md`
**Scope reviewed:** revised plan vs. real `flutter_ppg 0.2.4` + `camera 0.12.0+1` source in pub-cache, the `example/` scaffold (pubspec, `main.dart`, `Info.plist`, `AndroidManifest.xml`), and the kit's `ARCHITECTURE.md` / `rules/base.md`.

## Code Review Summary

**Files Reviewed:** plan + 6 verification targets (2 package sources, 4 example-app files)
**Risk Level:** 🟢 Low — all round-1 blockers are fixed and every "verified" API fact now matches source.

### Context Gates

- **Architecture (`ARCHITECTURE.md`):** ✅ PASS. All work is confined to `example/`; the plan explicitly forbids touching `lib/src/` or the public barrel this milestone (line 12), honoring "the barrel is the contract" and "self-contained, validated through `example/` first." No boundary violation.
- **Rules (`rules/base.md`):** ✅ PASS. Naming (`snake_case.dart`), example-local `nlog`-style logging with no `mind_mobile`/app-logger dependency, typed-states-not-exceptions (`CoverageOutcome` never throws), and "add packages only via `flutter pub add`" (Task 2 now uses `flutter pub add camera flutter_ppg`, line 38) are all respected. The round-1 WARN (I1) is closed.
- **Roadmap:** Not gated — flagged Phase-2 hardware-feasibility spike; no milestone-linkage requirement. No skill-context file present (`.ai-factory/skill-context/aif-review/SKILL.md` absent).

### Round-1 issues — all resolved

- **C1 (blocker) — `SignalQualityAssessor` not exported → won't compile.** ✅ Fixed. I re-confirmed the `flutter_ppg` barrel exports only `flutter_ppg_service`, `models/ppg_signal`, `models/ppg_config`, `frame_rate_detector`, `rr_interval_analyzer`, `models/filter_result` — `SignalQualityAssessor` is **not** among them. The plan now inlines the check (lines 23, 52): `bool covered(double raw) => raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax;`. This is byte-for-byte what `SignalQualityAssessor.isFingerPresent` does (`quality_assessor.dart:45-46`: `return rawIntensity > fingerPresenceMin && rawIntensity < fingerPresenceMax;`), and `fingerPresenceMin/Max` default to `30.0/250.0` (`ppg_config.dart:64-65`) — exactly as stated.
- **I1 — missing direct `camera` / `flutter_ppg` deps.** ✅ Fixed. Confirmed both are still merely `transitive` in `example/pubspec.lock`; Task 2 (line 34-39) now adds an explicit `flutter pub add camera flutter_ppg` step gated before any `auto_detect/` file is written, satisfying `depend_on_referenced_packages` under `flutter_lints ^6`.
- **I2 — wrong `CameraDescription` lens-type comment.** ✅ Fixed. Task 3 (line 43) now carries the corrected comment ("`lensType` exists but is frequently `unknown`… probe in `availableCameras()` order") and additionally captures `lensType` into the `RearCamera` descriptor as free signal for note 03.

### Critical Issues

None. The code described in Tasks 3–4 compiles against the real API surface:
- `PPGSignal` exposes `rawIntensity`, `quality` (`SignalQuality.poor|fair|good`), `snr`, `frameRate`, `isFPSStable` — all confirmed (`ppg_signal.dart`).
- `processImageStream(Stream<CameraImage>) → Stream<PPGSignal>` yields a real `rawIntensity` on **every** frame, including the pre-FPS-stable buffer-filling branch (`flutter_ppg_service.dart:177` yields `rawIntensity: intensity` before the early `continue`), so finger-presence works during warm-up + dwell with no wait for stabilization. The ~21-frame budget at `ResolutionPreset.low` for a 700 ms dwell is sound.
- `CameraController(..., imageFormatGroup:)`, `setFlashMode(FlashMode.torch/off)`, `startImageStream(callback)`, `dispose()` all verified against `camera-0.12.0+1`.
- Current `example/ios/Runner/Info.plist` has **no** `NSCameraUsageDescription` and the Android manifest has **no** `CAMERA` permission — Task 1 correctly adds both (and correctly leaves `camera.flash` `uses-feature` non-required).

### Minor Notes / Suggestions (non-blocking)

- **M1 — Task 6 wording: "Keep `WidgetsFlutterBinding.ensureInitialized()`".** The current `example/lib/main.dart` calls `runApp(const MyApp())` directly and does **not** call `ensureInitialized()`. So Task 6 must **add** it, not "keep" it. The required outcome (it must be present before `availableCameras()`) is correct; only the verb is misleading. Worth a one-word tweak so the implementer doesn't assume it already exists and skip it.
- **M2 — `extractRedChannel` throw-path is silent frame loss, not a crash.** In `processImageStream`, a frame whose red-channel extraction throws is swallowed with `continue` (no yield). With a *wrong* `imageFormatGroup` the more dangerous case is the opposite — it returns garbage intensity without throwing (silent bad signal). The plan already flags verifying the format per platform (line 18) and feeding the result to note 03; no change needed, just confirming the risk is acknowledged and correctly characterized.
- **M3 — Permission prompt is implicit.** The spike relies on `CameraController.initialize()` triggering the OS prompt and maps a denied-access `CameraException` to `AutoDetectError.permissionDenied` (line 57). That is the right minimal approach for a spike; the full `permission_handler` denied/permanently-denied flow is explicitly deferred to Phase 9 (note 15/18). Acceptable. On a cold first run a denial mid-round-trip will surface as `permissionDenied` on the first camera and abort the pass — fine for retry semantics.
- **M4 — Post-teardown frame guard.** Task 4 step 3/5 already require checking `controller.isClosed`/stream-closed before `add` and a strict single-controller teardown order. Good — this is the one real concurrency hazard in the design and it is handled.

### Positive Notes

- Correctly scoped as a throwaway `example/` spike with a clean Phase-5 (`note 08`) productionization handoff — no premature `lib/src/` commitment.
- Sequential single-controller round-trip with mandatory teardown between cameras respects the "cameras cannot be opened concurrently" hardware constraint.
- Locking on **coverage** (finger-presence) rather than confirmed pulse is the right discriminator, cleanly deferring warm-up/pulse confirmation to the next phase.
- Typed `CoverageOutcome` / `AutoDetectError` (never throwing) matches the kit's "typed states, not exceptions across the boundary" rule even at example scope.
- Coarse-rebuild discipline (aggregate counters, not per-frame `setState`) directly addresses the documented FPS-starvation risk.
- The inlined coverage test keeps the spike free of any `flutter_ppg/src/` private import — the cleanest possible resolution of C1.

### Verdict

All round-1 blockers (C1, I1, I2) are resolved and independently re-verified against package source. Remaining items are minor wording/awareness notes (M1–M4) that do not block implementation. The plan is accurate, architecturally compliant, and correctly scoped.

PLAN_REVIEW_PASS
