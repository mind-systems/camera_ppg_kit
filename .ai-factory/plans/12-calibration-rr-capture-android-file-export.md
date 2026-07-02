# Plan: Calibration RR-capture + Android file export

## Context
A plain-Dart recorder in `example/` that observes `CameraPpgService`'s streams, buffers every `RrInterval` with a monotonic elapsed clock and latest SQI, and writes one self-describing calibration JSON per run to the app external files dir so runs can be `adb pull`ed and compared against a manual pulse count off-device. Data layer only — the driving screen is a separate milestone (note 21).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dependency + recorder

- [x] **Task 1: Add `path_provider` to the example app**
  Files: `example/pubspec.yaml`
  Run `flutter pub add path_provider` **inside `example/`** (never hand-edit `pubspec.yaml`, per CLAUDE.md). Used only for `getExternalStorageDirectory()`. Do not add any storage permission — the external files dir is app-scoped, so no `WRITE_EXTERNAL_STORAGE` / runtime permission.

- [x] **Task 2: Recorder capture lifecycle — buffer intervals + metadata**
  Files: `example/lib/calibration/calibration_recorder.dart`
  New plain-Dart class `CalibrationRecorder`. Imports limited to `dart:async`, `dart:convert`, `dart:io`, the kit barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`), `package:path_provider/path_provider.dart`, and the example log helper (`../auto_detect/log.dart`). It observes `CameraPpgService` (from `../services/camera_ppg_service.dart`) — it **never** creates a `CameraPpgSession`, controller, or torch (no second camera owner; note 01 concurrency rule).
  - Hold the effective-run params as fields: `RrAcceptance`, `SessionPolicy`, `String? cameraId`, plus a `DateTime startedAt` and an internal `Stopwatch`.
  - Buffer captured beats in a private in-memory list of records, each `{ int tMs, int rrMs, bool isArtifact, String sqi }`. Keep the latest `SignalQuality` in a field (default a sensible initial, e.g. `SignalQuality.poor`) stamped onto each interval as it arrives. Add a `bool _done` flag.
  - `void start(CameraPpgService service, RrAcceptance acceptance, SessionPolicy policy, {String? cameraId})` — called by the screen at the same moment it calls `service.startMeasurement(...)`. Reset buffers/flags, capture the passed params as the effective params for the run, record `startedAt = DateTime.now()`, start (`reset` + `start`) the `Stopwatch`, and subscribe to the service's three streams:
    - `qualityStream` → store the latest `SignalQuality` in the field.
    - `rrStream` → append `{ tMs: stopwatch.elapsedMilliseconds, rrMs: rr.intervalMs, isArtifact: rr.isArtifact, sqi: <latest quality>.name }`. Append **every** interval, artifacts included (the peak-halving we hunt lives in the short/artifact ones). Use the stopwatch for `tMs`, not `RrInterval.timestamp` (device-clock caveat, note 05).
    - `stateStream` → on `MeasurementState.done`, stop the stopwatch and set `_done = true` (finalizable). Do **not** auto-write — the buffer stays in memory for an explicit `save()`.
  - `void stop()` — cancel the three subscriptions, stop the stopwatch, keep the buffer for saving. Idempotent / safe if called when never started.

- [x] **Task 3: Recorder `save()` — summary, JSON serialization, file write** (depends on Task 2)
  Files: `example/lib/calibration/calibration_recorder.dart`
  Add `Future<String> save({int? countedBeats, int? countWindowSeconds})` — callable after `stop()`/`done` so the tester can enter their count first; computes the summary, serializes JSON, writes the file, returns the absolute path. Each call writes a fresh filename — overwrites nothing.
  - **Dir:** `(await getExternalStorageDirectory())!` + `/calibration/`; create it if absent (`Directory(...).create(recursive: true)`).
  - **Name:** `calib_<yyyyMMdd_HHmmss>.json` derived from `startedAt` (format manually from the `DateTime` fields, zero-padded — do not add an `intl` dependency).
  - **Summary:** `totalIntervals` = buffer length; `acceptedIntervals` = count of `isArtifact == false`; `artifactIntervals` = the rest; `meanAcceptedRrMs` = mean of `rrMs` over `isArtifact == false` only (guard the empty-accepted case → `null` or `0`, and keep `kitBpm` consistent); `kitBpm` = `(60000 / meanAcceptedRrMs).round()`.
  - **Params serialization:** `acceptance` = `{ minRrMs, consistencyThreshold, coldStartBeats, medianWindow }` read off the `RrAcceptance` instance; `policy` = `{ warmupMs: warmupDuration.inMilliseconds, targetMs: targetDuration.inMilliseconds, silenceMs: silenceWindow.inMilliseconds, sqiFloor: sqiFloor.name }`. Serialization lives here in the recorder, not on the kit models (models stay import-free per ARCHITECTURE).
  - **JSON object** (`schemaVersion: 1`): `startedAt` (ISO-8601 `startedAt.toIso8601String()`), `durationMs` (`stopwatch.elapsedMilliseconds`), `cameraId`, `acceptance`, `policy`, `manualCount` (`{ beats, windowSeconds }` or `null` when `countedBeats` is null), `summary`, and `intervals` (the buffered records array). Encode with `JsonEncoder.withIndent('  ')`, write via `File(path).writeAsString(...)`, return the absolute path. Optionally emit a single coarse `ppgLog` with the written path (milestone-level only — the screen owns user-facing surfacing).

## Verify (manual, on-device — see spec note 20)
Run a measurement, stop, `save()` → a `calib_*.json` lands in `/sdcard/Android/data/com.mind.camera_ppg_kit_example/files/calibration/`; `adb pull` retrieves it; it parses; `intervals.length` matches beats seen; `summary.kitBpm` is plausible; a deliberate finger-off segment shows `poor` sqi + `isArtifact` intervals in the array.
