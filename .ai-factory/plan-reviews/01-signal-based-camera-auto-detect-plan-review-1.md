# Plan Review: Signal-based camera auto-detect (round 1)

**Plan:** `.ai-factory/plans/01-signal-based-camera-auto-detect.md`
**Scope reviewed:** plan vs. real `flutter_ppg 0.2.4` + `camera 0.12.0+1` source in pub-cache, the example app scaffold, and the kit's `ARCHITECTURE.md` / `rules/base.md`.
**Risk Level:** 🟡 Medium — the design is sound and architecturally compliant, but one "verified" API fact is wrong (code as specified will not compile) and one dependency step is missing.

---

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** ✅ PASS. The plan correctly confines all work to `example/` and explicitly forbids touching `lib/src/` or the public barrel this milestone. This honors the "barrel is the contract" and "self-contained, validated through example/ first" principles. No boundary violation.
- **Rules (`rules/base.md`):** ⚠️ WARN. The plan respects file naming (`snake_case.dart`), the example-local logging helper (no `mind_mobile` / app-logger dependency), and the "no throwing across the boundary — typed states" rule (`detectCoveredCamera` returns `CoverageOutcome`, never throws). **However** the rule "Add packages only via `flutter pub add` — never hand-edit `pubspec.yaml`" intersects with a missing step — see Important Issue I1.
- **Roadmap:** Not gated — this is a flagged Phase-2 hardware-feasibility spike; no milestone-linkage requirement applies. No skill-context file present (`.ai-factory/skill-context/aif-review/SKILL.md` absent).

---

## Critical Issues

### C1 — `SignalQualityAssessor` is NOT exported by the `flutter_ppg` barrel; code as written will not compile
The plan lists this under "Relevant API facts (**verified**)" (line 22) and uses it in Task 3 step 3:
> `SignalQualityAssessor.fromConfig(config).isFingerPresent(double rawIntensity)`

I checked `~/.pub-cache/hosted/pub.dev/flutter_ppg-0.2.4/lib/flutter_ppg.dart`. The barrel exports **only**:
```
flutter_ppg_service, models/ppg_signal, models/ppg_config,
frame_rate_detector, rr_interval_analyzer, models/filter_result
```
`SignalQualityAssessor` lives in `lib/src/quality_assessor.dart` and is **not re-exported**. So `import 'package:flutter_ppg/flutter_ppg.dart';` followed by `SignalQualityAssessor.fromConfig(...)` is an *undefined name* compile error. The only way to reach it is `import 'package:flutter_ppg/src/quality_assessor.dart';` — a reach into another package's `src/`, which is a lint/anti-pattern and itself transitively pulls `package:flutter_ppg/src/models/ppg_signal.dart`.

**Fix (simpler than the original):** drop the dependency on `SignalQualityAssessor` entirely and inline the finger-presence test, which is trivial and uses only the *exported* `PPGConfig`:
```dart
// isFingerPresent is literally: raw > fingerPresenceMin && raw < fingerPresenceMax
const cfg = PPGConfig();
bool covered(double raw) =>
    raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax; // 30..250 defaults
```
This is exactly what `SignalQualityAssessor.isFingerPresent` does (verified in `quality_assessor.dart`), needs no private-src import, and keeps the spike self-contained. Update both the "Relevant API facts" block and Task 3 to use this form.

---

## Important Issues

### I1 — Missing step: add `camera` and `flutter_ppg` as direct dependencies of the example app
Task 3/4 code imports `package:camera/camera.dart` and `package:flutter_ppg/flutter_ppg.dart` directly from `example/lib/auto_detect/`. But `example/pubspec.yaml` currently declares only `camera_ppg_kit` (path) and `cupertino_icons` — `camera` and `flutter_ppg` are merely *transitive* deps of the kit.

The code will resolve and run (they're in `pubspec.lock`), but `flutter analyze` under `flutter_lints ^6.0.0` will raise `depend_on_referenced_packages` for every direct import of a non-declared package. Per the project rule, this must be fixed with `flutter pub add` (not by hand-editing pubspec). Add an explicit step before Task 3:
```
cd example && /usr/local/bin/flutter pub add camera flutter_ppg
```
Recommend folding this into Task 1 (or a new Task 1b) so the dependency exists before any `auto_detect/` file is written.

### I2 — Task 2 comment is factually wrong: `CameraDescription` *does* expose a lens type
Task 2 instructs adding a comment that "`CameraDescription` exposes no lens-type/focal info in `camera ^0.12`." This is incorrect. In `camera_platform_interface 2.13.0`, `CameraDescription` has a `final CameraLensType lensType` field (`enum CameraLensType { wide, telephoto, ultraWide, unknown }`), defaulting to `unknown`.

The plan's *practical conclusion* still holds — on Android the logical back camera reports `unknown`, and iOS population is inconsistent — so "most-likely-covered first reduces to `availableCameras()` order" remains a reasonable operating assumption. But the comment should be corrected to: *"`CameraDescription.lensType` exists but is frequently `unknown` (esp. Android logical back), so we cannot reliably rank lenses by type; probe in `availableCameras()` order."* Also consider capturing `lensType` into the `RearCamera` descriptor — it's free signal for the device-support matrix (note 03).

---

## Minor Notes / Suggestions

- **Per-frame `rawIntensity` availability confirmed.** I verified `FlutterPPGService.processImageStream` yields a `PPGSignal` with a real `rawIntensity` on *every* frame, including the buffer-filling / pre-FPS-stable early-exit branches. So finger-presence works immediately during the 400 ms warm-up + 700 ms dwell without waiting for FPS stabilization — the plan's timing budget is sound. (At `ResolutionPreset.low` ≈ 30 fps, 700 ms ≈ ~21 frames, so the ≥ 0.6 covered-fraction threshold has adequate samples.)
- **Camera/torch/stream API all verified** against `camera-0.12.0+1`: `availableCameras()`, `CameraController(desc, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ...)`, `initialize()`, `setFlashMode(FlashMode.torch/off)`, `startImageStream(callback)`, `dispose()`, and `CameraDescription{ name, lensDirection, sensorOrientation }` (+ `lensType`) are all correct. `CameraLensDirection.back` is the right filter.
- **Stream bridge teardown — guard against post-close adds.** When wiring `startImageStream(callback)` → `StreamController<CameraImage>`, ensure the callback checks `controller.isClosed` before `add`, since camera frames can fire briefly after you decide to tear down. Plan's teardown order (cancel sub → `service.dispose()` → close controller → `setFlashMode(off)` → `controller.dispose()`) is otherwise correct; consider stopping the image stream / nulling the callback before disposing to avoid a late `add` on a closed sink. A non-broadcast `StreamController` is fine (single listener).
- **Android CAMERA permission is already merged** by `camera_android_camerax`'s own manifest, so the Task 1 addition is harmless/redundant-but-fine; `camera.flash` `uses-feature` is optional (don't mark `required="true"` or it would hide the app on flash-less devices — the plan doesn't, good).
- **imageFormatGroup ↔ red-channel extraction:** the plan rightly flags verifying `flutter_ppg`'s `extractRedChannel` against the chosen format per platform (iOS `bgra8888`, Android `yuv420`). Keep that as an explicit on-device check feeding note 03; a wrong format yields valid frames but garbage intensity (silent failure, not a crash).

---

## Positive Notes

- Correctly scoped as a throwaway example-app spike with a clean productionization handoff to Phase 5 (`note 08`) — no premature `lib/src/` commitment.
- Sequential single-controller round-trip with mandatory teardown between cameras correctly respects the "cameras cannot be opened concurrently" hardware constraint.
- Locking on **coverage** (finger-presence) rather than a confirmed pulse is the right discriminator for this milestone and cleanly defers warm-up/pulse confirmation to the next phase.
- Typed `CoverageOutcome` / `AutoDetectError` result (never throwing) matches the kit's "typed states, not exceptions across the boundary" rule even though it's example-local.
- Coarse-rebuild discipline (aggregate counters, not per-frame `setState`) directly addresses the documented FPS-starvation risk.

---

## Verdict

Solid design, architecturally compliant, and correctly scoped — but **not ready as written**: following Task 3 literally produces non-compiling code (C1), and the example is missing the direct `camera` / `flutter_ppg` dependencies its own imports require (I1). Resolve C1 and I1, and correct the lens-type comment (I2), then proceed.

Changes requested — not approving this round.
