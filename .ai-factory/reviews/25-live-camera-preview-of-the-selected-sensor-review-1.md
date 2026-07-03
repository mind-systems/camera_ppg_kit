# Code Review: Live camera preview of the selected sensor (round 1)

## Scope
Reviewed the code changes for plan 25 across three source files:
- `lib/src/api/camera_ppg_session.dart` — new `Widget? buildPreview()` + `package:flutter/widgets.dart` import.
- `example/lib/services/camera_ppg_service.dart` — new `CameraPpgSession? get session` accessor.
- `example/lib/screens/source_screen.dart` — new `_previewCard()` and its insertion into `build()`.

Doc-only changes (`notes/19`, `ROADMAP.md`, plan/note artifacts) were not reviewed for correctness beyond confirming they carry no code.

## Verification performed

**Kit surface — `buildPreview()` (session, lines ~162–176).**
- Null-safety is correct: reads `_controller` into a local, returns `null` when the local is `null` or `!controller.value.isInitialized`, else `CameraPreview(controller)`. `CameraValue.isInitialized` is a valid field; `CameraPreview` and `CameraController` come from the already-present `package:camera/camera.dart` import. No new leaked type — the signature is `Widget?` only.
- The dartdoc claim "`null` … during the pre-lock auto-detect probe" is accurate: grep confirms the **sole** `_controller =` assignment is line 366 in `start()`, reached only *after* the coverage round-trip locks a sensor and after `controller.initialize()`. The probe's transient controllers (`controller.initialize()` at line 759) are locals that never reach `_controller`, so `buildPreview()` cannot surface an intermediate probed sensor.
- Ordering vs the `warmup` emit is sound: in `start()`, `_controller = controller` precedes `_setState(MeasurementState.warmup)`, and `controller.initialize()` ran earlier — so on the first `warmup`-driven rebuild the controller is non-null and initialized, and the preview appears exactly when intended.
- The added `import 'package:flutter/widgets.dart';` alongside the existing `foundation.dart` introduces no ambiguity (widgets re-exports the same foundation declarations) and no clash with `camera`/`flutter_ppg` symbols.

**Service accessor (`session` getter).**
- Returns the kit type `CameraPpgSession?`, not a `Widget`, preserving the documented no-`flutter`/no-`camera` invariant of the plain-Dart service. `null` while idle (a fresh session per measurement), non-null while running — matches the dartdoc.

**Source screen `_previewCard()`.**
- Reads `buildPreview()` fresh on every build (`ref.read(...).session?.buildPreview()`) — never cached — so it cannot retain a stale texture across a stop. Rebuilds are driven by the top-of-`build()` `ref.watch(lifecycleProvider)`, giving the placeholder → live-texture flip on `starting → warmup` and the reverse on teardown, per the plan.
- Null branch renders `AsyncEmpty('no preview — start the source')` (a real widget-kit type); non-null branch boxes the preview in `ClipRRect` + `AspectRatio(3/4)`. Presentation only; Start/Stop, signal, camera-override, and `[debug]` cards untouched.

**Teardown-window behavior.** During `stopMeasurement()`, `_setLifecycle(stopping)` is emitted before `_session = null` and `session.dispose()`, so a `stopping` rebuild may still read a live controller and render the preview briefly; the subsequent `_setLifecycle(idle)` rebuild (after dispose nulls `_controller` and clears `_session`) reverts to the placeholder. Recreating the `CameraPreview`/`Texture` around a controller that is then disposed is handled gracefully by Flutter (stale texture id renders nothing) and is immediately followed by the idle rebuild — no crash path, consistent with the plan's "returns null after teardown" intent.

## Findings
None. The change is minimal, matches the plan, keeps the barrel/no-flutter invariants intact, and has no runtime correctness, null-safety, or lifecycle races. The one item the plan explicitly defers — whether preview coexists with `startImageStream` without starving FPS — is a device-verify concern, not a code defect, and correctly carries no preemptive throttling code.

REVIEW_PASS
