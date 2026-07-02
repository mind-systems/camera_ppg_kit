# Example — Calibration Screen (Pure Consumer, 60s Countdown)

**Date:** 2026-07-03
**Source:** ROADMAP Phase 7 re-decomposition — **supersedes the prior auto-stop/camera-lifecycle design of this note**; note 22 (source shell), note 20 (`CalibrationRecorder`), note 16 (`CameraPpgService`), note 09 (why `MeasurementState.done` is unreachable), calibration handoff #1

## Key Findings

- The calibration screen is a **pure consumer** of the already-flowing RR stream. The source is owned by the service and started on the **Source screen** (note 22); this screen owns **no** camera, warm-up, or session lifecycle. This reframe is the fix: every bug in the prior design came from the screen owning the measurement lifecycle (setState-after-dispose, timers armed on failed lock, tab-leave partial runs, stale-`stateProvider` Start gate).
- The **60 s is only a recording window** — data to teach the algorithm not to count the dicrotic notch (systole) as a beat — **not** a session limit. The kit's measurement session is open-ended (RR streams as long as the source runs).
- The window is bounded by a **screen-owned countdown** (`1:00 → 0:00`), independent of the kit's `SessionPolicy`/`MeasurementState`. The committed `CalibrationRecorder` (note 20) records the window via `start`/`stop`/`save`; its `done`-finalize path stays **dormant** (an open-ended session never reaches `MeasurementState.done`, note 09).
- The all-mounted shell (note 22) means a mid-recording navigation to another **kit-side** screen no longer kills anything — the screen stays mounted, the source keeps streaming, the recorder keeps buffering. The elaborate tab-leave-abort machinery of the prior design is simply **gone**.

## Details

### Precondition — the source must already be running

Started on the Source screen (note 22). At **record start**, check `ref.read(cameraPpgServiceProvider).isMeasuring` (`camera_ppg_service.dart:72` — authoritative service state, unlike `stateProvider` which can read stale after an external stop). If not measuring, show guidance ("Start measurement on the Source screen first") and do **not** begin recording — this is what prevents an empty/degenerate file.

### Recording flow (`example/lib/screens/calibration_screen.dart`, new)

- **Start recording** — `ppgTap('calib_record_start')`; verify `isMeasuring` (above); start a `Timer(const Duration(seconds: 60), _finish)` **and** a 1 Hz `Timer.periodic` driving the countdown display; read the **actual in-force config** from the shared `sessionConfigProvider` (note 22 — the `RrAcceptance`/`SessionPolicy` the Source screen's knobs last applied) and call `_recorder.start(service, config.acceptance, config.policy)` to begin buffering. Recording the *actual* config (not fresh defaults) is what keeps the JSON honest when the `[debug]` knobs are tuned. Set screen-local `_recording = true`.
- **`_finish()`** (shared by the 60 s timer and the optional manual Stop) — cancel + null both timers, `_recorder.stop()`, `_recording = false`, `_recorded = true` (enables Save). `ppgLog` a coarse "calib recording complete" milestone. Idempotent (guard so the manual Stop racing the auto-timer finalizes once).
- **Manual Stop** (optional, before 0:00) — routes through `_finish()`; the window is then shorter than 60 s and `countWindowSeconds` written at Save reflects the **actual** elapsed seconds, not a fixed 60.

### Save

- Counted-beats input — one optional numeric `TextField`.
- **Save** — `ppgTap('calib_save')`; `final path = await _recorder.save(countedBeats: beats, countWindowSeconds: <actual elapsed seconds>);` then `if (!mounted) return;` guard, show `path` as `SelectableText` + `ppgLog` it. Enabled only when `_recorded`.

### Display (quiet — no charts, no animation; FPS is load-bearing, note 03 / NFR)

- Large **countdown** (`m:ss` remaining, or `1:00` before start), driven only by the 1 Hz timer — never rebuilt on RR ticks.
- Large **display-only BPM** (`bpmProvider`) — a sanity check for the tester, labelled as such; not the reference.
- Small **SQI** chip + **`MeasurementState`** label (from the existing providers) so the tester sees the signal is good/measuring before trusting the count.
- Counted-beats field, Save button, saved-path text.

### State ownership (the single invariant that fixes the prior design)

- `_recording` (bool) — gates **Start recording** (disabled while recording). Keyed off this screen-local flag, **never** `stateProvider`.
- `_recorded` (bool) — gates **Save**.
- `dispose()` cancels both timers (the screen normally stays mounted in the IndexedStack shell; `dispose` fires only on app teardown). No `setState` after `await` without a `mounted` guard.
- The screen **never** calls `startMeasurement`/`stopMeasurement` or touches a controller/torch — the source is note 22's concern.

## Guards

- Pure consumer: opens no session/controller/torch, issues no start/stop of measurement (note 22 owns the source).
- Recorder (note 20) unchanged — used via `start`/`stop`/`save`; `done`-finalize dormant.
- Recorded params are the **actual** in-force config read from the shared `sessionConfigProvider` (note 22), so a run tuned via the `[debug]` knobs is described truthfully in the file — never a fresh-defaults stand-in.
- **Known minor edge (dev tool):** navigating to **Raw** mid-recording stops the kit source (note 22 exclusivity), so the buffer stops growing; the resulting file self-evidently holds few intervals for its window rather than silently misrepresenting a full minute. Not worth machinery for a developer instrument.

## Verify

- Source running → **Start recording** → countdown `1:00 → 0:00` → auto-finish → enter "62" → **Save** → adb path shown; the pulled file (note 20) has `manualCount.beats == 62`, `windowSeconds ≈ 60`, and a matching interval series.
- Source **not** running → **Start recording** shows guidance, writes no file.
- Navigate to Kit-API mid-recording and back → recording continues, source keeps streaming (note 22 all-mounted shell).
