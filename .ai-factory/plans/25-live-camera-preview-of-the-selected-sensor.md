# Plan: Live camera preview of the selected sensor

## Context
Expose the kit session's live camera texture as a `Widget?` and render it boxed on the example Source screen, so the operator can *see* which lens auto-detect locked and whether the finger fully covers it — the verification affordance feeding the de-halving re-evaluation (notes 29/30). The preview must be backed by the session's own single controller (rear camera + torch cannot open twice, note 01), never a second controller, and must never leak the `CameraController` across the barrel.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Kit surface

- [x] **Task 1: Add `buildPreview()` to `CameraPpgSession`**
  Files: `lib/src/api/camera_ppg_session.dart`
  Add a public method `Widget? buildPreview()` on `CameraPpgSession` that returns `CameraPreview(_controller!)` when `_controller != null && _controller!.value.isInitialized`, and `null` otherwise. `CameraPreview` and `CameraController` already come from the existing `import 'package:camera/camera.dart';` (line 3); add `import 'package:flutter/widgets.dart';` for the `Widget` return type (only `foundation.dart` is imported today). The signature is `Widget?` only — a `package:flutter` type that is clean across the barrel; the internal `CameraPreview` wraps `package:camera` but no `camera`/`CameraController` type appears in the signature. Do NOT add a getter that exposes `_controller` itself. Place the method near the stream getters (around lines 134–159) and dartdoc it: reads the existing controller only, so it returns non-null only between lock and teardown (`null` while idle, during the pre-lock auto-detect probe, and after `stop`/`dispose` null `_controller`). Touch nothing in the frame-path / `_release` teardown invariants (notes 07/13).

- [x] **Task 2: Enumerate the new surface in the note-19 API freeze** (depends on Task 1)
  Files: `.ai-factory/notes/19-drop-in-api-freeze.md`
  `buildPreview()` lands on the already-exported `CameraPpgSession`, so the barrel (`lib/camera_ppg_kit.dart`) needs no new `export` line — verify this and add no export. Record the additive kit-surface change in note 19's "What crosses the barrel (the frozen surface)" section: add `buildPreview() → Widget?` to the `CameraPpgSession` bullet as a post-freeze deliberate addition (note 19 Guards: "additions are a deliberate post-freeze act"), noting it returns a `package:flutter` `Widget` and leaks no `camera`/`CameraController` type — consistent with the freeze's leaked-type pitfall. This keeps the freeze honest for `mind_mobile` (which will want a "press your finger" preview).

### Phase 2: Example wiring

- [x] **Task 3: Bridge the session to the example without breaking the service's no-flutter invariant** (depends on Task 1)
  Files: `example/lib/services/camera_ppg_service.dart`
  `CameraPpgService` is plain Dart with a hard invariant (spec note 16, dartdoc lines 12–14): **no `flutter`/`flutter_riverpod`/`camera`/`flutter_ppg` imports**. It therefore must NOT declare a `Widget? buildPreview()` (a `package:flutter` type). Instead add a getter `CameraPpgSession? get session => _session;` returning the kit type — this preserves the invariant and lets the screen reach `buildPreview()`. Dartdoc it as an example-only accessor for the live preview surface (null when idle, fresh instance per measurement).

- [x] **Task 4: Render the boxed preview on the Source screen, gated on lifecycle** (depends on Tasks 1, 3)
  Files: `example/lib/screens/source_screen.dart`
  Add a `_previewCard()` `SectionCard(title: 'Preview', ...)` and insert it into the `build()` `ListView` (e.g. between `_controlCard` and `_signalCard`, with the existing `SizedBox(height: 16)` spacing). In the card, read `ref.read(cameraPpgServiceProvider).session?.buildPreview()`; when non-null wrap it in an `AspectRatio` (+ `ClipRRect` for rounded corners to match the card) so the texture is boxed; when null show a placeholder (reuse `AsyncEmpty('no preview — start the source')` from the widget kit). Rebuild is already driven by the `ref.watch(lifecycleProvider)` call at the top of `build()`, so the placeholder → live-texture flip happens on the `starting → warmup` transition — never cache the widget across a stop (call `buildPreview()` fresh every build; it returns null after teardown). Add a `ppgLog`/`ppgTap` only if a coarse milestone is warranted per the example logging convention — do not log every rebuild. Presentation only: leave Start/Stop, camera-override, signal, and `[debug]` cards untouched.

## Notes for the implementer
- **FPS coexistence is a device-verify concern, not a code task.** Preview + `startImageStream` on one controller at `ResolutionPreset.low` is expected to coexist cheaply; per the spec, if on-device testing shows the preview measurably starves the frame stream, that is a finding to **report**, not to hide or silently work around. No throttling/removal code should be added preemptively.
- Do not expose the raw `CameraController` anywhere — the only new cross-boundary types are `Widget?` (kit → example) and `CameraPpgSession?` (service → screen, example-internal).
