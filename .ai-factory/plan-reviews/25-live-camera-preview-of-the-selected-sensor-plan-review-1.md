# Plan Review: Live camera preview of the selected sensor

## Code Review Summary

**Files Reviewed:** 4 (plan + 3 target sources) plus barrel, note 19, note 35, ROADMAP, widget kit, providers, ARCHITECTURE
**Risk Level:** 🟢 Low

Verified the plan against the governing spec (`.ai-factory/notes/35-camera-preview-surface.md`), the ROADMAP line, and the actual code it targets. The plan is accurate, internally consistent, and correctly grounded in the current codebase. No blocking issues.

### Context Gates
- **Spec (note 35):** ALIGNED. Every claim in the plan traces to the spec — `Widget? buildPreview()` returning `CameraPreview(_controller!)` when `_controller != null && _controller!.value.isInitialized` else `null`, lifecycle-gated boxed render with the "no preview — start the source" placeholder, FPS coexistence framed as a report-not-hide device concern, no raw controller leak, frame-path/teardown invariants untouched.
- **Spec imprecision correctly resolved (WARN → resolved):** note 35 line 35 and ROADMAP line 70 both say "export via the barrel." The plan (Task 2) correctly recognizes that `buildPreview()` lands on the already-exported `CameraPpgSession` (barrel line `export 'src/api/camera_ppg_session.dart';`), so **no new export line is needed**. This is the right reading, not a deviation — a naive "add an export" would have been wrong. Good catch by the plan.
- **ARCHITECTURE.md:** ALIGNED. The pure-processing boundary ("`src/processing/` holds no Flutter/`camera` imports") is not touched — the change lands in `src/api/`, where importing `package:flutter/widgets.dart` is legitimate (the file already imports `package:flutter/foundation.dart` and `package:camera/camera.dart`). Note 19 enumeration (Task 2) satisfies the "adding to the public surface is a deliberate act" rule.
- **RULES (rules/base.md present):** No violation observed.
- **ROADMAP:** Task maps to line 70; Spec tag matches. Sibling task (line 71, "Expose which camera auto-detect locked") is correctly declared independent and out of scope.

### Critical Issues
None.

### Verification notes (all confirmed correct)
- **Task 1 imports:** `Widget` requires `package:flutter/widgets.dart`; only `foundation.dart` is imported today (confirmed line 5). `CameraPreview`/`CameraController` already available via `package:camera/camera.dart` (line 3). Importing both `foundation.dart` and `widgets.dart` is safe — `widgets.dart` re-exports `foundation` from the same origin, so no ambiguous-import error, and existing `defaultTargetPlatform`/`TargetPlatform` usages keep resolving.
- **Task 1 lifecycle semantics:** `_controller` is assigned (line 349) *before* `_setState(MeasurementState.warmup)` (line 357), and nulled in `_release()` (line 435). So `buildPreview()` returns non-null only between lock and teardown, null during the pre-lock auto-detect probe (probe uses local controllers, never `_controller`) and after stop/dispose — exactly as the plan's dartdoc claims.
- **Task 3 invariant:** `CameraPpgService` is plain Dart with the no-`flutter`/`camera` import invariant (dartdoc lines 12–14). Exposing `CameraPpgSession? get session` (a kit-barrel type) rather than a `Widget?` correctly preserves that invariant. `_session` is already the field name (line 48).
- **Task 4 wiring:** `SectionCard`, `AsyncEmpty` (single positional `String message`), `lifecycleProvider`, and `cameraPpgServiceProvider` all exist and are already imported in `source_screen.dart`. The rebuild driver — `ref.watch(lifecycleProvider)` at the top of `build()` (line 125) — is real, so the placeholder→texture flip fires on the `starting → warmup` lifecycle emit, at which point `_controller` is already set and initialized. Insertion point (between `_controlCard` and `_signalCard`) is consistent with the existing `ListView` composition.
- **Double null-safety after stop:** `stopMeasurement()` nulls `_session` before disposing, and `buildPreview()` also returns null after `_controller` is nulled — so `session?.buildPreview()` yields null via either guard. The "call fresh every build, never cache" instruction is honored by the design.

### Minor / advisory (non-blocking)
- **Task 4 — AspectRatio value is unspecified, and the true sensor ratio is intentionally unreachable.** Because the controller is deliberately hidden, the screen cannot read `controller.value.aspectRatio`, so the `AspectRatio` wrapper must use a hard-coded ratio. `CameraPreview` itself only fills its constraints, so a mismatched ratio letterboxes or mildly distorts the image. This is acceptable for a hardware-debugging preview (and matches the spec's own "aspect-ratio boxed" imprecision), but the implementer should pick a sensible fixed ratio (e.g. `3/4`) and treat exact geometric fidelity as out of scope. Not blocking; worth a one-line note in the widget so a later reader doesn't "fix" it toward the hidden controller.
- **Logging:** Task 4's "add `ppgLog`/`ppgTap` only if a coarse milestone is warranted" is the correct posture per the example logging convention (`CLAUDE.md`) — a pure presentation card driven by an already-logged lifecycle stream does not need its own log. Fine as written.

### Positive Notes
- The plan respects every teardown/frame-path invariant (notes 07/13) — `buildPreview()` only reads the existing controller and adds nothing to `_release`/`_tearDownHandles`.
- Cross-boundary type discipline is exact: the only new types crossing are `Widget?` (kit → example) and `CameraPpgSession?` (service → screen, example-internal); no `camera`/`CameraController` type appears in any signature.
- Task dependencies (1←2, 1←3, 1+3←4) are correct and minimal.
- The FPS-coexistence risk is correctly framed as a device-verify finding to report, with an explicit "add no throttling/removal preemptively" guard — matching the spec.

PLAN_REVIEW_PASS
