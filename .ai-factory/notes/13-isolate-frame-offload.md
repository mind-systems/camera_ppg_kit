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

### Guards

- One long-lived isolate per measurement; tear it down in `stop()`/`dispose()` (Phase 11 lifecycle) — a leaked isolate keeps the torch path warm and drains battery.
- Only sendable values cross the port: `TransferableTypedData` + ints in, RR/quality value types or `double`s out. No `CameraImage`, `CameraController`, or `PPGSignal` over the `SendPort`.
- Do not throw across the isolate boundary for expected states — mirror the no-exceptions-across-the-channel rule: send typed values, surface errors as data.
- Offload is transparent to the public surface (note 07): the barrel streams `RrInterval`/`SignalQuality`/`MeasurementState` exactly as before — this is an internal performance change, one revertable concern.
