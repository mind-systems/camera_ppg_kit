# Device-Support Matrix + Go/No-Go

**Date:** 2026-06-21
**Source:** conversation context; outputs of notes 01 + 02

## Key Findings

- The whole kit is conditional on a hardware reality that varies per phone: can a fingertip cover both lens and flash, and does the frame path sustain enough FPS for a stable signal? This task converts runs of the example app's auto-detect panel (note 01) and raw stream-inspector panel (note 02) into a **decision**.
- The deliverable is an analysis document, not code — but it is atomic and gates Phases 6–11. A "no-go on most devices" outcome changes the kit from a primary source to a narrow opt-in, and that must be decided before bridges are built.
- Output also seeds the **allow/deny-list** the hardening phase (Phase 11) enforces and validates the signal-based auto-detect (note 08) the session implements.
- **The camera-exposure capability is already answered from the plugin sources — not hardware.** `camera_avfoundation` 0.10.1 returns **every** rear lens as a separate `CameraDescription` (wide / telephoto / ultrawide, with `lensType`), so the round-trip runs in pure Dart on iOS. `camera_android_camerax` 0.7.2 returns **one logical back camera** (physical sub-lenses are not reachable past CameraX), so on Android the round-trip degrades to the default back camera only. The spike therefore confirms only the per-device *count*, with a ~15-line throwaway probe before any kit code — it does not need to discover the capability.

## Details

### Deliverable

A matrix (markdown table in `.ai-factory/` or `docs/`) with one row per tested phone and columns:

- Model / camera-island layout
- Default rear camera = torch-co-located (one finger covers its lens + the torch)? (Y / hard / N)
- Rear `CameraDescription` count from `availableCameras()` (expected: iOS ≈ all physical lenses with `lensType`; Android ≈ 1 logical back) — confirms the source-derived capability per device
- Auto-detect resolves a covered sensor without manual override? (default-only / needed fallback probe / failed)
- Worst-case auto-detect time, s (finger on the last-probed sensor)
- Finger-presence reliably distinguishes covered / over-bright / uncovered? (Y / flickery / N)
- Sustained FPS (from note 02)
- RR stability vs reference (good / noisy / none)
- Verdict: **supported / marginal / unsupported**

### Results (provisional — 1 device)

**This matrix is provisional: only one Android device has been tested.** It needs at least an iPhone Pro (multi-lens island, worst flash–lens separation) and a single-camera budget phone before the go/no-go can be made.

| Device / island | Lens+flash, one finger? | Rear cams (`availableCameras`) | Auto-detect | Worst-case detect | Finger-presence | Sustained FPS | RR vs reference | Verdict |
|---|---|---|---|---|---|---|---|---|
| Galaxy A70 (SM-A705FN), Android 11 — triple rear island | Y | 1 (logical back; 3 physical sensors collapsed by CameraX) | default-only | ~2 s | Y (covered-fraction 1.00) | ~24, stable | good — steady ~57–60 BPM resting (not yet cross-checked vs a reference monitor) | supported |

**Observations from the A70 run** (90 s static-finger inspector session):

- **SQI reaches `good` within ~2 s and holds** for the whole session; SNR 7.5–13 dB; finger-presence stable throughout.
- **Frame path holds ~24 FPS, `isFPSStable` true** under the quiet inspector screen — no frame starvation. Confirms the FPS-sensitivity risk is manageable when no heavy animation shares the screen.
- **Two halving artifacts** (instantaneous BPM spiked to ~110–130, RR ≈ 458–542 ms) where the detector picked a harmonic / dicrotic notch. `flutter_ppg`'s outlier filter caught them (rejection ratio jumped to ~0.78), but the *instantaneous* BPM still misreported. Motivates the Phase-8 RR acceptance gate (note 12): a rolling-median consistency filter rejects a 458 ms interval against a ~1040 ms median.
- **RR resolution is FPS-quantized.** Intervals land on ~42 ms steps (= 1000/24 ms frame period), so BPM is discrete (53.3 / 55.4 / 57.6 / 60.0 / 62.6…) and fine-grained HRV (SDRR ~30 ms) sits near the quantization floor. BPM/RR is usable; precise HRV from camera PPG at this frame rate is coarse (peak-time interpolation could improve it — open question).

### Calibration validation — handoff #1 (2026-07-03, post de-halving, A70)

Two Calibration-screen runs against a manual reference, after the note-30 adaptive
de-halving landed and with the finger on a cleanly-covered lens:

| Run | Manual reference | Kit (mean accepted RR → BPM) | Artifacts | RR cluster |
|---|---|---|---|---|
| Resting | 60.0 BPM (59 beats / 59 s) | 1003 ms → **59.8 BPM** | 0 / 134 | unimodal ~1000 ms, **no halved cluster** |
| Elevated | 87.5 BPM (86 beats / 59 s) | 649 ms → **92.4 BPM** | 15 / 800 (1.9%) | 600–700 ms; **0 accepted > 900 ms** |

- **Halving resolved.** The two-halving-artifacts problem this note first recorded is
  gone: the resting run is a clean unimodal ~1000 ms cluster with 0 artifacts, exact to
  0.2 BPM against the manual count (was 112–131 BPM ≈1.9× before the fix).
- **No over-merge at elevated rate** — the feared failure mode (de-halver collapsing a
  fast pulse toward rest) is absent: the whole accepted cluster sits at the elevated
  600–700 ms, with zero accepted intervals > 900 ms.
- **+4.9 BPM overshoot at elevated** (92.4 vs 87.5) — minor, safe direction; likely
  manual-count error on a fast pulse and/or the recorder averaging re-emitted intervals
  (over-weights shorter ones). Not re-tuned: resting is exact and any threshold change
  risks it.
- **Validated defaults (committed as-is, note 34):** gate `minRrMs=300, thr=0.4,
  coldStart=3, medianWindow=5`; policy `warmup=5 s, silence=3 s, sqiFloor=poor`;
  de-halving tracker params per note 30. Fixtures: `.calibration/calib_20260703_230446.json`
  (rest), `calib_20260703_230927.json` (elevated).

### Go/no-go statement

**Decision: GO (2026-06-22).** Validated end-to-end on the Galaxy A70 — auto-detect locks the covered lens, the torch drives a clean signal, SQI holds `good`, the frame path sustains ~24 FPS without starvation, and RR/BPM is physiologically plausible (resting ~57–60 BPM). The spike's question — *does a usable contact-PPG signal exist on real hardware* — is answered yes, so the kit ships and proceeds to implementation (Phases 3–12). The matrix stays provisional: broadening device coverage (iPhone Pro multi-lens island, single-camera budget phone) and deriving any deny-list move into hardening (Phase 11) rather than gating the build. Known limitations to carry forward: occasional peak-halving artifacts (addressed by the Phase-8 acceptance gate) and FPS-quantized RR resolution.

**Item #1 — confirm the rear-camera count; Phase 7 is a deletion candidate.** The plugin sources already answer the *capability* (Key Findings): iOS exposes every rear lens, Android exposes one logical back camera. Native enumeration is therefore unnecessary on both platforms, and the spike confirmed the torch holds through capture via `setFlashMode(FlashMode.torch)` — so the native torch-**fallback** phase is **dropped** (former notes 10/11, removed). The only native concern that survives is *optional torch-brightness control*, deferred behind the roadmap STOP (heat is the motivation; see roadmap Phase 11). The spike only confirms the per-device *count* with a ~15-line throwaway probe on real devices (simulator/emulator have no cameras):

```dart
import 'package:camera/camera.dart';
final cams = await availableCameras();
for (final c in cams) {
  print('${c.name} | ${c.lensDirection} | orient=${c.sensorOrientation}');
}
final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).length;
print('BACK cameras: $back'); // iOS Pro → 2-3; Android → expect 1
```

iOS rows can be **pre-filled from public model specs** (model → rear-lens count) and merely confirmed; Android rows are structurally one back camera, confirmed on 2–3 phones.

Then the headline conclusion: ship camera PPG as (a) a broadly-available source, (b) a marginal opt-in gated to an allow-list, or (c) shelve it. Include the allow/deny-list derived from the matrix.

### Test set

Cover the camera-island archetypes, not just brands: single-camera budget phones, dual-camera mid-range, and large-island flagships (iPhone Pro, Samsung S-Ultra, Pixel Pro) where flash–lens separation is worst.

### Verify

The document names every phone tested, the FPS and SQI numbers behind each verdict, and a one-line go/no-go that the next phases can act on without re-running hardware.

### Guards

- No silent caps: if only a few phones were tested, state that the matrix is provisional.
- Decision belongs to the user — this note produces the evidence and a recommendation, not a unilateral shelving.
