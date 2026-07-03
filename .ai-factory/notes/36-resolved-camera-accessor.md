# Expose which camera auto-detect locked

**Date:** 2026-07-03
**Source:** conversation context (verify camera selection is correct)

## Why

To verify selection you must know *which* lens auto-detect actually locked, not just see
its image. Today the kit surfaces no such accessor —
`source_screen.dart:255-262` documents the gap explicitly: "the current barrel exposes
no such accessor (`CameraPpgSession` surfaces only rr/quality/state/fingerPresence,
never the resolved `CameraDescription`)". On multi-lens phones (iOS every lens, Samsung's
clustered rear module) knowing the locked lens id/type is the most direct confirmation
the round-trip picked the right sensor; the live preview (note 35) is the visual
complement. Cheaper and independently shippable from the preview — ship even if the
preview hits a snag.

## The change

- `CameraPpgSession`: after auto-detect locks (`_lockCoveredCamera`, ~line 349) or a
  pinned `useCamera(id)` resolves, expose the active camera as a
  `CameraPpgCameraInfo` (the existing barrel model, `camera_ppg_camera_info.dart`) — a
  `resolvedCamera` accessor and, since lock happens asynchronously inside `start()`, a
  small stream/notifier the host can watch (fires on lock, clears to null on
  `_release()`). No `camera` `CameraDescription` crosses the barrel — map to
  `CameraPpgCameraInfo` at the edge, as `availableCameras()` already does.
- Example `source_screen.dart`: show "Locked lens: `<id>` (`<lensType>`)" in the camera
  card once resolved, "auto-detecting…" during the probe, "—" when idle. This directly
  answers "did it pick the right camera?" in text.

## Guards

- Additive kit-surface change — enumerate in note 19's API freeze (Phase 10).
- Map to `CameraPpgCameraInfo`; never leak `CameraDescription`/`camera` types (note 07).
- Clears to null on stop/`_release()` so a stale lens never shows after a measurement
  ends (aligns with the note-32/33 lifecycle correctness work).
- Independent of note 35 — neither task depends on the other.

## Verify

- On device: after Start, the Source card names the locked lens; on a multi-lens device
  confirm it is the lens the finger is actually over. After Stop it clears.
- With `useCamera(id)` set, the resolved lens equals the pinned id (auto-detect skipped).
