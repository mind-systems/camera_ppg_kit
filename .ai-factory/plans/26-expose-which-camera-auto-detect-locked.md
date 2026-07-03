# Plan: Expose which camera auto-detect locked

## Context
Surface the lens the auto-detect round-trip (or a pinned `useCamera(id)`) actually locked as a readable `CameraPpgCameraInfo` on `CameraPpgSession`, and render it as text in the example Source screen — the text complement to note 35's live preview, making camera selection verifiable without reading pixels.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Kit surface

- [x] **Task 1: Add `resolvedCamera` accessor + lock/clear stream to `CameraPpgSession`**
  Files: `lib/src/api/camera_ppg_session.dart`
  Expose the currently-locked lens as the existing barrel model, mapping at the edge so no `package:camera` type crosses the boundary:
  - Add a `StreamController<CameraPpgCameraInfo?> _resolvedCameraController` (broadcast), constructed alongside the other controllers in the constructor initializer list, and close it in `dispose()` next to the other `await _*.close()` calls.
  - Add a `CameraPpgCameraInfo? _resolvedCamera` field (defaults `null`), a `CameraPpgCameraInfo? get resolvedCamera` accessor, and a `Stream<CameraPpgCameraInfo?> get resolvedCameraStream => _resolvedCameraController.stream`. Document that it is `null` while idle / during the pre-lock auto-detect probe, non-null between lock and teardown, and clears back to `null` on stop/`_release()` — mirroring `buildPreview()`'s lifecycle doc.
  - Add a private `_setResolvedCamera(CameraPpgCameraInfo? next)` helper that dedupes on the `id` (or on `null`), stores `_resolvedCamera`, and emits on the controller guarded by `!_resolvedCameraController.isClosed` — same shape as `_setState`.
  - Extract the `CameraDescription → CameraPpgCameraInfo` mapping used inside `availableCameras()` (`id: d.name`, `lensType: d.lensType.name`, `flashAvailable: true`) into a private `CameraPpgCameraInfo _toCameraInfo(CameraDescription d)` helper, and call it from both `availableCameras()` and the lock path so the edge-mapping lives in one place.
  - In `start()`'s successful promotion block (where `_controller`/`_frameIsolate`/`_sub` are assigned, just before `_setState(MeasurementState.warmup)`), call `_setResolvedCamera(_toCameraInfo(description))`. `description` already holds the resolved lens for both the auto-detect and pinned-`useCamera` paths, so a single call covers both.
  - In `_release()`, call `_setResolvedCamera(null)` alongside the other reset work so a stale lens never lingers after a measurement ends (place it with the `_acceptance.reset()`/`_dehalving.reset()` cleanup).
  - No barrel edit: `camera_ppg_kit.dart` already exports the whole session file and `camera_ppg_camera_info.dart`, so the new members and model are public automatically. (The note-19 Phase-10 API-freeze enumeration is a separate future task — do not touch note 19 here.)

### Phase 2: Example display

- [x] **Task 2: Show "Locked lens" in the Source screen** (depends on Task 1)
  Files: `example/lib/screens/source_screen.dart`
  Surface the resolved lens in the "Camera override" `SectionCard`, read fresh each build off the service's session — the same pattern `_previewCard()` uses for `buildPreview()`, so it rides the existing `ref.watch(lifecycleProvider)` rebuild:
  - Read `final resolved = ref.read(cameraPpgServiceProvider).session?.resolvedCamera;` inside `_cameraOverrideCard`.
  - Add a `LabelRow` (from the widget kit) showing the locked lens with three states driven by the `locked`/lifecycle input and `resolved`: idle → `'—'`; `resolved != null` → `'${resolved.id} (${resolved.lensType})'`; locked-but-not-yet-resolved (probe in flight) → `'auto-detecting…'`. Label the row `'Locked lens'`.
  - Update the now-stale dartdoc on `_cameraOverrideCard` (the paragraph at ~lines 306–310 stating "Does not show which sensor auto-detect itself locked — the current barrel exposes no such accessor…") to describe the new behavior instead — this is the exact gap the milestone cites.
  - Presentation only — no change to Start/Stop, camera-pin, or `sessionConfigProvider` wiring; the `camera_ppg_service.dart` no-`flutter` invariant stays intact (the screen calls `session.resolvedCamera` itself, no service getter added).
