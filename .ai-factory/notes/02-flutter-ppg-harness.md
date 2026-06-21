# flutter_ppg Finger-Video Harness

**Date:** 2026-06-21
**Source:** `flutter_ppg` 0.2.4 docs (pub.dev); `camera` plugin API; conversation context

## Key Findings

- `flutter_ppg` consumes a `Stream<CameraImage>` via `FlutterPPGService.processImageStream(...)` and emits `PPGSignal` objects containing: raw + filtered red-channel values, **RR intervals (ms, bounded 300–2000 via `PPGConfig`)**, a Signal Quality Index (Good/Fair/Poor), SNR, finger-presence, and detected FPS / stability metrics. It does **not** compute BPM or HRV — the consumer derives those.
- Detection FPS is auto-derived from the frame stream (supports 24/25/30/60). The docs explicitly warn that heavy UI work degrades FPS and signal quality — so the harness must run on a quiet screen and we must record the **sustained** FPS, not the nominal one.
- This is the **raw stream-inspector panel of the single example app** (note 14) at its Phase-2 stage — the instrument that answers "does a usable PPG signal exist on this phone, and at what FPS?". Its numbers are the raw input to the go/no-go (note 03); the panel later grows into the full stream inspector.

### Camera setup that flutter_ppg needs

- `CameraController` with the **auto-detected** camera (note 01: the default rear camera first, fallback sequential probe), `ResolutionPreset.low` (high res wastes bytes; PPG needs intensity not detail), `enableAudio: false`, torch **on** (`setFlashMode(FlashMode.torch)`), and a fixed/locked exposure where the platform allows it (auto-exposure chases the signal and flattens it).
- Start the image stream with `controller.startImageStream` and forward each `CameraImage` to `FlutterPPGService`.

## Details

### Scope

A panel in the `example/` app that, given the auto-detected sensor (note 01): turns the torch on, streams `CameraImage`s into `FlutterPPGService`, and displays/logs the live `PPGSignal` fields — RR (ms), derived BPM (`60000/intervalMs` for display only), SQI, SNR, finger-presence, and **measured FPS**. No acceptance policy, no session lifecycle — raw passthrough. The FPS readout stays visible in the final inspector (note 14), where preview + rebuilds are exactly what can starve frames.

### What to capture per run

- Sustained FPS under a static screen.
- SQI distribution over a 60 s still-finger hold.
- RR stability (visual + logged) against a reference (a worn pulse or a second app).
- **Finger-presence reliability** — now the *selection linchpin* (note 01), not just guidance: confirm it cleanly distinguishes covered vs uncovered, flips correctly when the finger lifts, and does not flicker mid-hold (a flickering presence signal would thrash auto-detect).

### Verify

On each test phone, a 30–60 s still-finger hold yields a stable RR stream with mostly Good/Fair SQI and ≥24 sustained FPS. Failures (no signal, <24 FPS, SQI stuck Poor) are recorded against that device in note 03.

### Guards

- Real device only.
- Keep the screen visually minimal — any animation here corrupts the very FPS number we are trying to measure.
- Raw passthrough only at this stage; the production session lives in Phase 5, and this panel grows into the full stream inspector (note 14).
