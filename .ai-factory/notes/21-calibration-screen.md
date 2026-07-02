# Example — Calibration Screen (3rd Tab)

**Date:** 2026-07-02
**Source:** ROADMAP `---STOP---` calibration handoff (#1); note 20 (capture + export); note 14 (tabbed shell, Kit-API tab); note 16 (`CameraPpgService`); `example/lib/main.dart` (`_TabShell`)

## Key Findings

- The calibration loop is deliberately dead-simple: **Start → the tester counts their own pulse for a fixed one-minute run → the run auto-stops at 60 s → enter the count → Save → I pull the file (note 20) and compare.** The screen exists to make counting easy (a big, quiet elapsed timer + live BPM to sanity-check against) and to trigger the note-20 export.
- **Auto-stop is a screen-owned wall-clock timer, not the kit's `MeasurementState.done`.** The kit's `SessionPolicy.targetDuration` accrues only *measuring* time — it excludes the 5 s warm-up and pauses during `poorSignal` (note 09), so `done` lands well past 60 s of wall clock and drifts run-to-run. Calibration needs the **counting window and the capture window to be the same wall-clock interval** so the manual mean-BPM and the kit mean-BPM cover the same seconds. So the screen fires its own `stop()` at exactly `kCalibrationRunDuration` (60 s from Start); the policy `done` transition is never reached in a normal run (the wall-clock stop always precedes it) and is not relied on for stopping.
- It gets its **own tab**, not a mode inside the Kit-API tab — a calibration session wants a stripped, distraction-free surface (an animated/busy screen starves FPS, note 03), and keeping it separate keeps the Kit-API dogfood tab unchanged.
- It reuses the **same `CameraPpgService`** (note 16) as the Kit-API tab: auto-detect, kit defaults, the same streams. No new session plumbing — it drives `startMeasurement()`/`stopMeasurement()` and feeds note 20's recorder from the existing providers.
- Running the **kit defaults** is the point: we are measuring what today's defaults produce so we can retune them. The recorder stamps the effective params into every file (note 20), so each run is self-describing even as defaults change between rebuilds.

## Details

### Tab shell — `example/lib/main.dart`

Extend `_TabShell` from two tabs to three: **Raw**, **Kit API**, **Calibration**.

- `TabController(length: 2 → 3)`; add a `Tab(text: 'Calib')` and the `CalibrationScreen()` to the `TabBarView`.
- **Generalize the camera-release-on-leave rule.** Today `_onTabChanged` releases the service camera only when leaving the Kit-API tab (`_kitApiTabIndex == 1`). The Calibration tab (index 2) drives the **same** `CameraPpgService`, so the rear camera + torch (which cannot be opened concurrently, note 01) must be released when leaving **either** service-owning tab, including a Kit-API ⇆ Calibration switch. Replace the single-index check with "previous index was a service-owning tab (1 or 2) and the selection changed" → `stopMeasurement()`. The Raw tab (0) still manages its own `CameraController` teardown as before. The same not-awaited-listener caveat and accepted residual race documented at `_onTabChanged` carry over unchanged.

### Screen — `example/lib/calibration/calibration_screen.dart`

A `ConsumerStatefulWidget` reading the existing providers (`stateProvider`, `bpmProvider`, `qualityProvider`, note 14's `stream_providers.dart`) — no `StreamBuilder`, no per-widget `.listen()` on the service (subscriptions live in providers / the recorder, per neiry's stream-ownership lesson).

Layout — kept visually quiet on purpose (no charts, no animation):

- **Start / Stop** — on Start: request camera permission (reuse note 15's `_checkAndRequestCameraPermission()` pattern), then call `CameraPpgService.startMeasurement()` **and** `CalibrationRecorder.start(RrAcceptance(), SessionPolicy())` together (defaults; pass `cameraId` only if a manual override is ever added — not required for v1), and arm the auto-stop timer (below). A single shared `_stop()` path — `stopMeasurement()` + `recorder.stop()` + cancel timers — is invoked by **both** the manual Stop button and the auto-stop timer, so the two finalize identically.
- **Auto-stop timer** — `const kCalibrationRunDuration = Duration(seconds: 60);` A `Timer(kCalibrationRunDuration, _stop)` armed on Start and cancelled on manual Stop / dispose / tab-leave. When it fires, the run finalizes exactly as a manual Stop would (torch off via the kit's ordered release), and the recorder's buffer covers the same 60 s the tester counted. Exposed as a named constant for now (change one line to run 30 s / 90 s trials); a UI field can come later if needed.
- **Elapsed timer** (large) — seconds since Start shown against the target, e.g. `0:23 / 1:00`, so the tester watches it approach one minute and knows when to stop counting. Drive it off a local `Timer.periodic(1s)` — coarse 1 Hz, cheap; do not rebuild on every RR tick. (A `1:00 → 0:00` countdown is an acceptable alternative display; the auto-stop is the timer above regardless.)
- **Live BPM** (large, display-only) — from `bpmProvider`, purely a during-run sanity check for the tester ("am I counting the same ballpark?"). Not the reference.
- **State + SQI** — small `MeasurementState` label and SQI chip so the tester knows warm-up is done and the signal held (`measuring`, `good`) before trusting their count.
- **Manual count input** — one small number field, "beats counted". The count window is fixed at the run duration (`kCalibrationRunDuration`), so it is not typed — it is written to the file as `windowSeconds` automatically. Optional; may be left blank.
- **Save run** — enabled once a run has finalized (auto-stop or manual Stop); calls `recorder.save(countedBeats: …, countWindowSeconds: kCalibrationRunDuration.inSeconds)`, then shows the returned absolute path on-screen (selectable text) **and** `ppgLog`s it, so the path to `adb pull` is unmistakable.

### Logging

Follow the example convention (CLAUDE.md): `ppgTap('calib_start')`, `ppgTap('calib_stop')`, `ppgTap('calib_save')` at the top of each handler; coarse milestones for run start / stop / file-written(path). One helper (`ppgLog`/`ppgTap`), no `print`.

## Guards

- Reuses `CameraPpgService`; opens no `CameraPpgSession`/controller/torch of its own (note 01). The tab-shell release rule is the single owner-arbiter across all three tabs.
- Runs kit **defaults** (`RrAcceptance()`/`SessionPolicy()`); no `[debug]` tuning knobs on this screen (that lives on the Kit-API tab, note 14) — a calibration run must measure the unmodified defaults, and the recorder records exactly which ones.
- Kit `lib/` untouched — `example/` only.

## Verify

- Three tabs present; entering Calibration and Start opens the camera once; switching to any other tab releases it (torch off) with no `CameraException` on return.
- Start → timer counts up toward `1:00` → `measuring`/`good` reached → **the run auto-stops at 60 s (torch off) with no Stop tap** → enter "62" → Save → a path is shown and logged; the pulled file (note 20) has `durationMs ≈ 60000`, `manualCount.beats == 62`, `manualCount.windowSeconds == 60`, and a matching interval series.
- Manual Stop before 60 s finalizes identically (shared `_stop()` path) and cancels the auto-stop timer — no double-stop, no torch left on.
- Kit-API ⇆ Calibration switch mid-run releases the first tab's camera before the second opens (no concurrent-open crash).
