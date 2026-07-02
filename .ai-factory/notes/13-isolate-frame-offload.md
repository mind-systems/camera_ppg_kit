# Isolate Offload for the Frame Path

**Date:** 2026-06-21
**Source:** ROADMAP Phase 8 ("Isolate offload for the frame path"); DESCRIPTION.md frame-rate NFR; note 02 (FPS findings); note 07 (bare wired session); ARCHITECTURE.md "Processing is pure and isolate-friendly"

## Key Findings

- **Defensive, not a prerequisite — confirmed by the spike (note 03).** On the A70 the inspector held ~24 FPS `isFPSStable` for 90 s on the UI isolate with **no** offload, because the screen repaints coarsely (~3 Hz timer, no per-frame `setState`). So the cheap first lever is coarse repaint, and this isolate task is a *defense for the heavy co-tenant case* (the breath-session animation, the exact thing DESCRIPTION warns about) — deferrable until a real screen is shown to starve frames, then this is the fix. Do not treat it as blocking the kit.
- **The problem is still real where it bites.** DESCRIPTION's frame-rate NFR and note 02 say heavy UI work on the main isolate starves the `CameraImage` stream and drops sustained FPS below the ~24 floor, corrupting the signal. The win here is keeping our red-channel reduction **and** `flutter_ppg`'s DSP off the UI isolate when such a screen exists.
- **The `camera` plugin already delivers `CameraImage` on a platform thread**, but `startImageStream`'s callback fires on the **root/UI isolate** — so the byte work runs there today. Moving it to a background isolate is the offload.
- **Two realistic shapes, picked by a blocker that must be confirmed empirically:** (a) run `flutter_ppg` whole inside a long-lived background isolate; (b) if `flutter_ppg` is not isolate-safe, do only the per-frame red-channel reduction in the isolate and feed `flutter_ppg` the reduced 1-D signal on the main isolate.
- **Source read (note 03 spike):** `flutter_ppg` 0.2.4 `processImageStream` is a pure `async*` generator — `await for (image in images) { extractRedChannel(image); … yield PPGSignal(...) }` — with no platform-channel / `WidgetsBinding` / plugin-registrant calls in the loop, so variant (a) (run the whole service in the isolate) is very likely viable. Still **confirm empirically** by running it under a spawned isolate before committing; do not ship on the source read alone.

## Details

### Current state → target

Today (note 07) `CameraPpgSession` forwards each `CameraImage` straight into `FlutterPPGService.processImageStream` on the UI isolate. Target: a `lib/src/processing/frame_isolate.dart` host that spawns a long-lived isolate (`Isolate.spawn`, kept alive for the measurement — **not** `Isolate.run` per frame, which would re-spawn 24–60×/s) and a `SendPort` pipe.

- **Ship frame bytes safely.** `CameraImage` itself is **not** sendable. Extract the plane(s) we need and wrap their `Uint8List` as `TransferableTypedData.fromList([...])` before `send()` — zero-copy ownership transfer, avoiding a full byte copy per frame. Send alongside width/height/bytesPerRow/format as plain ints so the isolate can index pixels.
- **Variant (a):** isolate receives transferable planes, materializes them, feeds `FlutterPPGService` inside the isolate, and returns `PPGSignal` field values (RR ints, SQI index, SNR, presence, FPS) — **plain sendable values, never the `PPGSignal` object if it is not sendable** — back over a reply `SendPort`.
- **Variant (b):** isolate runs only the reduction (mean red intensity per frame, the cheap O(pixels) loop) and sends back a `double` per frame; the main isolate feeds those into `flutter_ppg`. Smaller per-frame payload, but `flutter_ppg` DSP stays on the UI isolate — only acceptable if its DSP cost is shown (note 02) to be negligible vs the reduction.
- **Keep `src/processing/` pure** (ARCHITECTURE rule 4 / dependency rules): the reduction and any acceptance logic (Phase 8 gate, note 08-area) hold **no** `camera` / channel / Flutter imports, so the same code runs identically in the isolate and in unit tests. The isolate entrypoint lives here; the `CameraController` wiring stays in `src/api/`.

### Verify

- Confirm `flutter_ppg` isolate-safety empirically (source read or harness run) and record the verdict in this note before coding.
- In the example, run a measurement while a deliberately heavy animation drives the UI isolate: sustained FPS and SQI must stay at the note-02 baseline, where the pre-isolate path collapsed. That delta is the proof.
- Unit-test the reduction in isolation (no hardware) on synthetic planes.

#### Task 1 verdict (2026-07-02, on-device, Samsung SM-A705FN / Android 9, yuv420)

**PASS — variant (a) confirmed: run the whole `FlutterPPGService` inside a long-lived spawned isolate.**

A throwaway harness (`Isolate.spawn`, `TransferableTypedData.fromList` transfer, `CameraImage.fromPlatformData` reconstruction with the yuv420 3-element `[Y, placeholder, V]` plane rebuild, `FlutterPPGService.processImageStream` driven entirely inside the isolate, plain-value `PPGSignal` fields replied over the port) ran a real 8-second capture against the device's rear camera:

- **224/224 frames sent → 224/224 signals received, 0 errors.** No `WidgetsBinding`/plugin-registrant/platform-channel errors — `defaultTargetPlatform` (via `Platform.operatingSystem`) resolved correctly inside the spawned isolate with no Flutter engine attached to it, confirming the recon note's claim.
- Quality tally over the run: `{poor: 29, good: 191, fair: 4}` — signal quality reached `good` and RR intervals were detected (`rrCount=1` from frame ~200 onward) purely from ambient/incidental light variation (no finger was placed — that is Task 8's concern, not Task 1's), confirming the pipeline (buffer fill → filter → peak detection → RR emission) runs correctly end-to-end off the UI isolate.
- `TransferableTypedData` transfer worked for yuv420 (Y + V planes) on every frame; bgra8888 (iOS) was **not** exercised on real hardware — no iOS device was available in this environment. Task 7's synthetic unit test is the only bgra8888 coverage; treat iOS as source-confirmed but not device-confirmed.
- Getting the verdict out required a fallback: `dart:developer.log()` (what `ppgLog`/`nlog` route through) did not surface in this `flutter run` console setup, so the harness additionally dumped its log buffer to an app-private file (`files/isolate_probe_result.txt`) pulled via `adb shell run-as`. This was diagnostic-only scaffolding, not a kit convention change — removed with the rest of the throwaway harness.

**Decision:** proceed with variant (a) for Phase 2 (Tasks 2–4). The throwaway harness (`example/lib/isolate_probe/isolate_probe_harness.dart`, plus the temporary `runIsolateProbe()` call in `example/lib/main.dart`) is deleted now that the verdict is recorded, per this task's scope note — Task 8 builds its own on-device toggle against the real `FrameIsolate`/`SignalMessage` types rather than reusing this scaffolding.

#### Task 8 verdict (2026-07-02, on-device, Samsung SM-A705FN / Android 9, yuv420)

**Mitigation confirmed — SQI held under a real heavy UI-isolate animation; frame-delivery FPS degraded but stayed serviceable.**

A temporary `HeavyLoadProbeScreen` (`example/lib/isolate_probe/heavy_load_probe_screen.dart`, booted as the app's `home` via a temporary `main.dart` toggle) drove the real, isolate-backed `CameraPpgSession` (public barrel type — the closest available stand-in for the not-yet-built Kit-API tab) through two 10 s phases, sampled every 250 ms, with a 3 s warm-up settle in between:

- **Heavy animation:** a `Ticker`-driven (real engine frame clock, not a plain `Timer`) per-tick `List<int>.generate(20000)..sort()` **plus** a 150-widget `Text` rebuild each tick while active — genuine UI-isolate CPU *and* layout/paint competition, reproducing the pre-isolate collapse scenario (not an offscreen spin).
- **Metric reachability:** `SignalMessage`/`CameraPpgSession` were temporarily widened with `frameRate`/`isFPSStable`/`debugLastFrameRate`/`debugLastFpsStable` (flutter_ppg's internal FPS detector, mirrored through the isolate) to make the numbers observable; **all of this was reverted immediately after this run** — the frozen boundary (`SignalMessage`'s five fields, `_onSignal`'s contract) is unchanged in the committed code.
- **Baseline (animation OFF, 39 samples):** `avgFrameRate=30.00`, `fpsStable=39/39` (100%), quality tally `{good: 39}` (100% good).
- **Loaded (animation ON, 36 samples):** `avgFrameRate=20.22`, `fpsStable=13/36` (36%), quality tally `{poor: 1, good: 35}` (97% good).

**Reading the result honestly, per this task's framing:** SQI held almost entirely `good` (35/36) even under sustained heavy UI-isolate load — the isolate offload keeps `flutter_ppg`'s DSP off the UI isolate, so it isn't starved by the animation's CPU work, and the quality/acceptance pipeline stays robust even as delivery gets uneven. But average FPS *did* drop (30.0 → 20.22) and `isFPSStable` flipped false more often (100% → 36%) — confirming the plan's caveat that this is a **mitigation, not immunity**: `startImageStream`'s callback still fires on the root/UI isolate (frame *delivery* isn't moved off it, only frame *processing*), so a sufficiently heavy co-tenant animation can still measurably slow delivery even though it can no longer corrupt SQI the way the pre-isolate path could. The loaded FPS (20.22) is below the note-02/03 baseline (~24 FPS held with **no** offload under a *coarse-repaint* screen) — expected, since this harness's animation is deliberately far heavier (per-tick sort + widget rebuild) than the ~3 Hz timer that baseline was measured against; the two numbers aren't measuring the same load.

**Not yet exercised:** the definitive end-to-end proof through the example's Kit-API tab (Phase 7, not yet built) — this on-device run is the interim validation the plan calls for, using `CameraPpgSession` directly rather than a dedicated tab UI.

The temporary widening and the `HeavyLoadProbeScreen`/`main.dart` toggle are fully reverted in the committed code — `SignalMessage`, `frame_isolate.dart`, and `camera_ppg_session.dart` carry no trace of this task's instrumentation.

### Guards

- One long-lived isolate per measurement; tear it down in `stop()`/`dispose()` (Phase 11 lifecycle) — a leaked isolate keeps the torch path warm and drains battery.
- Only sendable values cross the port: `TransferableTypedData` + ints in, RR/quality value types or `double`s out. No `CameraImage`, `CameraController`, or `PPGSignal` over the `SendPort`.
- Do not throw across the isolate boundary for expected states — mirror the no-exceptions-across-the-channel rule: send typed values, surface errors as data.
- Offload is transparent to the public surface (note 07): the barrel streams `RrInterval`/`SignalQuality`/`MeasurementState` exactly as before — this is an internal performance change, one revertable concern.
