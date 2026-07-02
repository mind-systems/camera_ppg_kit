# Plan: Calibration screen (pure consumer, 60s countdown)

## Context
Add an example-only Calibration screen that consumes the already-flowing RR/quality/state
streams and runs a screen-owned `1:00 → 0:00` countdown bounding a `CalibrationRecorder`
window over the live source, then wire it into the all-mounted shell. The screen owns no
camera/warm-up/session lifecycle — it only commands the committed recorder (note 20) and
reads the in-force config from `sessionConfigProvider` (note 22).

## Settings
- Testing: no
- Logging: example convention only — `ppgTap` on every interaction, coarse `ppgLog` milestones (per `camera_ppg_kit/CLAUDE.md`). No kit `lib/` logging.
- Docs: no

## Scope guards (from spec notes 21 / 22 / 20)
- **`example/` only.** Do **not** touch kit `lib/`, `CalibrationRecorder` (note 20), `CameraPpgService` (note 16), or `sessionConfigProvider` — all are used as-is.
- **Pure consumer.** The screen never calls `startMeasurement`/`stopMeasurement`, opens no `CameraController`/torch, and never gates on `stateProvider`.
- **Start gate** = screen-local `_recording` flag (not `stateProvider`). **Record-start precondition** = `service.isMeasuring` (`camera_ppg_service.dart:72`).
- Recorder used via `start`/`stop`/`save` only; its `done`-finalize path stays dormant (open-ended session never reaches `MeasurementState.done`).

## Tasks

### Phase 1: Calibration screen

- [x] **Task 1: Scaffold the screen + recording lifecycle**
  Files: `example/lib/screens/calibration_screen.dart` (new)
  Create `CalibrationScreen extends ConsumerStatefulWidget`. State fields:
  a single owned `final CalibrationRecorder _recorder = CalibrationRecorder();`,
  `Timer? _finishTimer`, `Timer? _tickTimer`, `int _remainingSeconds = 60`,
  `int _windowSeconds = 0`, `bool _recording = false`, `bool _recorded = false`,
  `String? _savedPath`, and a `TextEditingController _beatsController` for counted-beats.
  Implement the recording lifecycle (no UI yet):
  - `_startRecording()` — `ppgTap('calib_record_start')`; read `service = ref.read(cameraPpgServiceProvider)`;
    if `!service.isMeasuring`, surface guidance ("Start measurement on the Source screen first")
    via a screen-local flag/SnackBar and **return without recording** (prevents an empty file);
    else read `config = ref.read(sessionConfigProvider)`, call
    `_recorder.start(service, config.acceptance, config.policy)`, then `setState` →
    `_recording = true`, `_recorded = false`, `_remainingSeconds = 60`, `_savedPath = null`.
    Arm `_finishTimer = Timer(const Duration(seconds: 60), _finish)` **and**
    `_tickTimer = Timer.periodic(const Duration(seconds: 1), ...)` that decrements
    `_remainingSeconds` (clamped at 0) inside `setState` — the 1 Hz timer drives only the
    countdown display, never a rebuild on RR ticks.
  - `_finish()` — idempotent (guard: `if (!_recording) return;`). Cancel + null both timers,
    `_windowSeconds = 60 - _remainingSeconds` (so a manual Stop before 0:00 records the actual
    elapsed window, not a fixed 60), `_recorder.stop()`, `setState` → `_recording = false`,
    `_recorded = true`; `ppgLog('calib recording complete')`.
  - `_stopManually()` — `ppgTap('calib_record_stop')` then routes through `_finish()`.
  - `dispose()` — cancel both timers, `_beatsController.dispose()`; no `setState` after any
    `await` without a `mounted` guard. (The screen normally stays mounted in the shell's
    `IndexedStack`; `dispose` fires only on app teardown.)

- [x] **Task 2: Save flow + quiet display UI** (depends on Task 1)
  Files: `example/lib/screens/calibration_screen.dart`
  Build the `build()`/UI (quiet — no charts, no animation; FPS is load-bearing):
  - Large **countdown** `m:ss` from `_remainingSeconds` (show `1:00` before start), driven only
    by the tick timer.
  - **Start recording** button — disabled while `_recording` (gated on the local flag, never
    `stateProvider`); **Stop** button (optional) calling `_stopManually()` while `_recording`.
  - Large **display-only BPM** from `ref.watch(bpmProvider)`, labelled "BPM (display-only)".
  - Small **SQI** chip (`ref.watch(qualityProvider)`) + **`MeasurementState`** label
    (`ref.watch(stateProvider)`) reusing the same colour/label mapping style as
    `kit_api_tab.dart` (deliberately its own copy — not a shared widget).
  - Counted-beats **`TextField`** (numeric, optional) bound to `_beatsController`.
  - **Save** handler `_save()` — `ppgTap('calib_save')`; `final beats = int.tryParse(_beatsController.text);`
    `final path = await _recorder.save(countedBeats: beats, countWindowSeconds: _windowSeconds);`
    then `if (!mounted) return;` guard, `setState(() => _savedPath = path)`, `ppgLog(path)`.
    Save button enabled only when `_recorded`.
  - Show `_savedPath` as a `SelectableText` when non-null (adb-pullable path).
  - Guidance line/banner when the last `_startRecording()` was blocked by `!isMeasuring`.

### Phase 2: Shell wiring

- [x] **Task 3: Add the Calibration branch to the shell** (depends on Task 2)
  Files: `example/lib/main.dart`
  Register the screen in the all-mounted shell (note 22): add a `calibration('Calibration')`
  case to the `_Branch` enum **before `raw`** (order = Source, Kit API, Calibration, Raw),
  add the matching `_Branch.calibration => const CalibrationScreen()` arm to `_screenFor`,
  and import `screens/calibration_screen.dart`. No other change is needed — `children`,
  `destinations`, and `selectedIndex` are already built by iterating `_Branch.values`, and the
  Raw-exclusivity hook keys off `_Branch.raw` (the enum, not a literal index), so inserting a
  branch is index-shift-safe. Confirm the Raw stop-hook and Source Start/Stop remain untouched.

## Verify (from spec note 21)
- Source running → **Start recording** → countdown `1:00 → 0:00` → auto-finish → enter a count →
  **Save** → adb path shown; pulled file has `manualCount.beats` matching, `windowSeconds ≈ 60`.
- Source **not** running → **Start recording** shows guidance, writes no file.
- Navigate Source ↔ Kit-API ↔ Calibration mid-recording and back → recording continues, source
  keeps streaming (all-mounted shell).
