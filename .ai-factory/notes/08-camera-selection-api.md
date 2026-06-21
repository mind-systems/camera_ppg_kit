# Camera Auto-Detect + Override API

**Date:** 2026-06-21
**Source:** conversation context; notes 01 (signal-based auto-detect), 04 (channel contract), 07 (session), 09 (warm-up window)

## Key Findings

- **Selection is signal-based auto-detect (note 01).** The interaction is **finger first, then Start**; on `start()` the session runs one round-trip over the rear sensors in **most-likely-covered-first order** (the former torch-proximity heuristic, demoted to probe priority), each with torch on and a short coverage dwell, and locks onto the first that reads **covered** — coverage (red-dominant, high DC, low variance, not over-bright), **not** a confirmed pulse, which the warm-up confirms after the lock. Zero host configuration.
- **Fail fast on no coverage.** If the round-trip finds no covered sensor, `start()` surfaces a typed `CameraPpgError` (note 06) and returns to idle; the user repositions and presses Start again. The torch flickers only during the single pass — there is no loop. **No new `MeasurementState` is introduced** (keeps notes 06/09/14/19 untouched): success enters `warmup` (note 09), failure returns to idle.
- The host still needs a **manual override** escape hatch for the rare device auto-detect mis-handles (the spike, note 03, will name them) and for testing: list the selectable rear cameras and let the host pin one before `start()`.
- Independently shippable from the bare session (note 07): the session works on auto-detect alone; this adds the override surface + the diagnostics list.
- **Enumeration is Dart-side, no native channel (note 03).** The rear-camera list comes straight from the `camera` plugin's `availableCameras()`: iOS returns every rear lens as a separate `CameraDescription` with `lensType` (so the round-trip has several to try), Android returns one logical back camera (so the round-trip is just the default back). The round-trip is the same code; its breadth differs by platform.

## Details

### Added to `CameraPpgSession`

- `Future<List<CameraPpgCameraInfo>> availableCameras()` — wraps the `camera` plugin's `availableCameras()` filtered to `lensDirection == back` (id = `CameraDescription.name`, plus `lensType` where the plugin offers it — present on iOS). The list exists for manual override and diagnostics.
- `void useCamera(String id)` — pins a camera, skipping auto-detect; must be called before `start()`; throws `StateError` if called mid-measurement.
- Default behaviour: if `useCamera` is never called, `start()` auto-detects via the one-shot round-trip (note 01).

`CameraPpgCameraInfo` is a small model (id + descriptive metadata map) — add to `lib/src/models/` and export.

### Verify

On a multi-camera phone: with a finger placed first, `start()` locks the covered sensor in one round-trip (observable: torch lights, signal appears) with no `useCamera` call; covering a different lens the torch still reaches also resolves. `start()` with no finger placed completes the round-trip, surfaces the typed `CameraPpgError`, and returns to idle (the example shows a retry prompt). `availableCameras()` lists rear sensors; `useCamera()` with a given id makes the next `start()` use exactly it. `useCamera()` during `measuring` throws.

### Guards

- Auto-detect is the default; override is never required.
- **Metadata is descriptive only** (id, lens type, `flashAvailable`) — the host reads it for display and override, never for selection.
- Override takes effect on the next `start()` — no mid-stream hot-swap (mirrors the SDK-reconfig-needs-restart discipline neiry hit).
- Keep metadata a map/plain fields, not a brittle enum, so new lens types from future devices don't break decoding.
