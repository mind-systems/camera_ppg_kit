# Example — Calibration RR-Capture + Android File Export

**Date:** 2026-07-02
**Source:** ROADMAP `---STOP---` calibration handoff (#1); note 12 (RR-gate), note 09 (session policy), note 03 (device matrix — FPS-quantized RR, peak-halving); note 16 (`CameraPpgService`); note 05 (`RrInterval`)

## Key Findings

- Calibration reference is **manual pulse count only** (decision recorded here): the tester counts beats over the run, the kit's numbers are pulled off-device, and the two averages are compared. Peak-halving/doubling (note 03) shows plainly in the mean-BPM ratio and in the raw interval column, so a mean-level reference is enough for this pass. No oximeter / chest-strap path is built.
- To compare off-device, a run must be **captured to a file** — the live BPM chip on screen is not enough. This task is the **data layer only** (recorder + JSON export); the screen that drives it is note 21.
- The file must land somewhere `adb pull` reaches **without root**: the app external files dir (`path_provider`'s `getExternalStorageDirectory()`), i.e. `/sdcard/Android/data/com.mind.camera_ppg_kit_example/files/calibration/`. App-owned scoped storage — no `WRITE_EXTERNAL_STORAGE`, no runtime permission.
- The file is **self-describing**: it carries the effective gate/policy params in force for that run, so successive runs with tweaked defaults stay comparable and I never have to guess which thresholds produced a given series.

## Details

### `example/pubspec.yaml` — add `path_provider`

No storage dependency today. Add with `flutter pub add path_provider` **inside `example/`** (never hand-edit `pubspec.yaml`, per CLAUDE.md). Used only for `getExternalStorageDirectory()`.

### Recorder — `example/lib/calibration/calibration_recorder.dart`

Plain-Dart, no Flutter/camera imports beyond the kit barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`) and `path_provider`. It does **not** own a session — it observes the existing `CameraPpgService` streams (note 16), so the same auto-detect / teardown / stream-ownership invariants hold unchanged.

Lifecycle:

- `start(RrAcceptance acceptance, SessionPolicy policy, {String? cameraId})` — called by the screen at the same moment it calls `CameraPpgService.startMeasurement()`. Resets in-memory buffers, starts an internal `Stopwatch` (the elapsed-ms clock for `tMs` below — monotonic, sidesteps `RrInterval.timestamp`'s device-clock caveat in note 05), and records the passed params as the "effective params" for the run.
- Subscribes to the service's `rrStream`, `qualityStream`, `stateStream`:
  - `qualityStream` → keep the **latest** `SignalQuality` in a field (stamped onto each interval as it arrives).
  - `rrStream` → append `{ tMs: stopwatch.elapsedMs, rrMs: rr.intervalMs, isArtifact: rr.isArtifact, sqi: <latest quality>.name }`. Every interval, artifacts included (the doubling we hunt is in the artifact/short ones).
  - `stateStream` → on `done`, stop the stopwatch and mark the run finalizable (the run keeps its buffer in memory; it is **not** auto-written — see save flow).
- `stop()` — called when the screen stops; cancels the three subscriptions, stops the stopwatch, keeps the buffer for saving.
- `Future<String> save({int? countedBeats, int? countWindowSeconds})` — computes the summary, serializes JSON, writes the file, returns the absolute path. Callable after `stop()`/`done` so the tester can enter their count first. Overwrites nothing — a fresh filename per call.

### File — location, name, schema

- Dir: `(await getExternalStorageDirectory())!` + `/calibration/` (create if absent).
- Name: `calib_<yyyyMMdd_HHmmss>.json` from `DateTime.now()` (the example app may read the wall clock freely — this is app code, not a workflow script).
- One run = one JSON object:

```json
{
  "schemaVersion": 1,
  "startedAt": "2026-07-02T14:03:11.123",
  "durationMs": 60000,
  "cameraId": "0",
  "acceptance": { "minRrMs": 300, "consistencyThreshold": 0.40, "coldStartBeats": 3, "medianWindow": 5 },
  "policy":     { "warmupMs": 5000, "targetMs": 60000, "silenceMs": 3000, "sqiFloor": "poor" },
  "manualCount": { "beats": 62, "windowSeconds": 60 },
  "summary": {
    "totalIntervals": 70, "acceptedIntervals": 64, "artifactIntervals": 6,
    "meanAcceptedRrMs": 968.0, "kitBpm": 62
  },
  "intervals": [
    { "tMs": 5210, "rrMs": 455,  "isArtifact": true,  "sqi": "good" },
    { "tMs": 5665, "rrMs": 1012, "isArtifact": false, "sqi": "good" }
  ]
}
```

- `acceptance`/`policy` are read off the `RrAcceptance`/`SessionPolicy` instances the run started with (public final fields; `Duration` fields serialized as `inMilliseconds`, `sqiFloor` as `.name`). When the screen passes plain `RrAcceptance()`/`SessionPolicy()` these are the kit's current defaults — exactly the numbers under calibration.
- `manualCount` is `null` when the tester did not enter a count.
- `summary.kitBpm` = `60000 / meanAcceptedRrMs` rounded; `meanAcceptedRrMs` over `isArtifact == false` only. These let the mean-vs-manual comparison happen at a glance; the raw `intervals` array is where doubling is eyeballed (a column of ~450s interleaved with ~1000s).

### Pull workflow (documented, not code)

```
adb shell ls /sdcard/Android/data/com.mind.camera_ppg_kit_example/files/calibration/
adb pull /sdcard/Android/data/com.mind.camera_ppg_kit_example/files/calibration/<file>.json
```

## Guards

- Recorder observes `CameraPpgService`; it never opens a `CameraPpgSession`, controller, or torch itself — no second camera owner (note 01 concurrency rule).
- No new runtime permission: the external files dir is app-scoped. Do **not** add `WRITE_EXTERNAL_STORAGE`.
- Kit `lib/` is untouched — this is `example/` only. Serialization lives in the recorder, not on the kit models (models stay import-free per ARCHITECTURE).

## Verify

- Run a measurement, stop, save → a `calib_*.json` appears in the dir; `adb pull` retrieves it; it parses; `intervals.length` matches the beats seen; `summary.kitBpm` is plausible.
- A deliberate finger-off segment shows `poor` SQI and `isArtifact` intervals in the array — proves per-interval SQI/artifact stamping works.
