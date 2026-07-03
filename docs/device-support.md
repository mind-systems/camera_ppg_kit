# Device support

Contact PPG depends on hardware that varies per phone: whether one fingertip can cover a rear lens **and** the torch at once, and whether the frame path sustains enough FPS for a stable signal. This page records what has been verified per device. Coverage is provisional — only one device has been measured so far.

## What makes a device usable

- A rear lens sits close enough to the torch that a single fingertip covers both.
- The frame path holds a stable frame rate — ~24 FPS is enough for usable RR.
- The signal-based auto-detect locks the covered lens.

## Tested devices

| Device | Rear cameras (`availableCameras()`) | Sustained FPS | Auto-detect | Verdict |
|---|---|---|---|---|
| Galaxy A70 (SM-A705FN), Android 11 | 1 logical back | ~24, stable | locks the default back | supported |

## Galaxy A70

- **Cameras.** `availableCameras()` returns one logical back camera (id `0`, lens type `unknown`). The three physical rear sensors — main, ultrawide, depth — are collapsed behind it by CameraX and are not individually selectable through the `camera` plugin.
- **Zoom.** Range is `min 1.0 / max 8.0`, digital only: `min 1.0` gives no zoom-out to the ultrawide, and there is no optical telephoto, so zoom crops the main sensor rather than switching physical lenses.
- **Frame path.** ~24 FPS with `isFPSStable`; SQI reaches `good` within ~2 s; SNR 7.5–13 dB.
- **RR resolution.** Intervals quantize to ~42 ms steps (the 1000/24 ms frame period), so BPM is discrete and fine-grained HRV sits near the quantization floor.

### Calibration (A70)

Against a manual beat count over a ~60 s window, with the committed defaults:

| Run | Manual reference | Kit | Artifacts |
|---|---|---|---|
| Resting | 60.0 BPM | 59.8 BPM | 0 / 134 |
| Elevated | 87.5 BPM | 92.4 BPM | 15 / 800 |

The resting run is a clean unimodal cluster near 1000 ms. The elevated run sits at 600–700 ms with no intervals collapsing back toward the resting rate, so a fast pulse is tracked rather than merged down; the ~5 BPM overshoot is on the safe side (an over-count, not a collapse).
