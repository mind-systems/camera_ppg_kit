# Adaptive de-halving — offline design against calibration fixtures

**Date:** 2026-07-03
**Source:** conversation context (calibration handoff #1)

## Key Findings

- Two on-device runs (`calib_20260703_161520.json`, `calib_20260703_163042.json`)
  show **peak-halving**: `flutter_ppg` emits ~2× the real beats. Manual reference
  67–69 beats/59 s ≈ 68–70 BPM (true RR ≈ 855–881 ms), but the intervals[] carry a
  bimodal distribution — a true cluster at ~800–1000 ms and a halved cluster at
  ~330–500 ms — and the kit reports 112–131 BPM (≈1.9× real).
- The neiry-ported acceptance gate (`lib/src/processing/rr_acceptance.dart`) does not
  just fail to fix this, it **inverts**: its free-floating rolling median migrates onto
  the more-numerous halved population (in run 1 a transitional run 917→708→583→500→458
  walked the median from 917 ms to 500 ms by ~5.7 s), after which it *accepts* the
  halved beats and *rejects* the true beats as artifacts (231 true beats discarded, 584
  halved beats accepted). Simulating the gate as coded reproduces the recorded
  `isArtifact` flags 868/868 — so the file is a faithful offline fixture.
- **No fixed threshold can solve this.** The user requires full 15–190 BPM support
  (RR 316–4000 ms). A halved beat (~430 ms) is numerically identical to a real 140 BPM
  beat, so any constant floor (`RrAcceptance.minRrMs`, or `flutter_ppg`'s
  `PPGConfig.minRRMs=300` which drives `PeakDetector.minDistance`) is simultaneously a
  max-HR cap. Rejected by constraint.
- `flutter_ppg` 0.2.4 *already* has an "adaptive minDistance"
  (`flutter_ppg_service.dart` `_minDistanceFromFps`/`_adaptiveMinDistance`) — but it
  adapts to **FPS, not to the measured heart rate** (`minDistanceFrames = fps *
  minRRMs/1000`). That is why halving survives: the min-distance is keyed on the wrong
  variable. The genuinely adaptive lever must track the *fundamental beat period* and
  scale rejection with the actually-measured rate.

## Goal of this task

Design-only. Build an **offline evaluation harness** (plain Dart under `test/` or a
throwaway script — NO device code, NO kit `lib/` changes) that replays the two
`.calibration/*.json` fixtures through candidate de-halving algorithms and scores each
against `manualCount`. Pick one approach and write its exact implementation shape into
note 30. Deliverable is a decision + evidence, not shipped code.

## Candidate approaches to evaluate

1. **RR-domain harmonic-pair merge.** Track the dominant beat period adaptively
   (rolling autocorrelation of the recent RR series, or a slow-tracking template of the
   accepted period). When two consecutive short intervals sum to ~the tracked period
   (within a proportional tolerance), merge them back into one beat. Rejection scales
   with the tracked rate → no fixed cap. Operates on the stream the kit already has
   (`SignalMessage.rrIntervals`), so it needs no `flutter_ppg` fork.
2. **Adaptively drive `flutter_ppg`'s `PPGConfig` peak params.** Re-instantiate /
   reconfigure `FlutterPPGService` with a `minRRMs` derived from the *current tracked
   BPM* (e.g. 0.5× the tracked beat period) rather than a constant. Stops halved peaks
   at the source but requires driving the config live and confirming the service honors
   it mid-stream (the frame isolate owns the service — `frame_isolate.dart:231`).
3. **Waveform-domain fundamental estimation.** Autocorrelation / FFT of the filtered
   PPG waveform to find the true fundamental, reject peaks off the fundamental. Most
   robust but needs the waveform, which `flutter_ppg` consumes internally — likely
   out of reach without a fork; evaluate feasibility only.

## Scoring

For each fixture, per candidate: derived BPM vs `manualCount` BPM (target: within
counting error, ≈±3), fraction of true-cluster beats retained, fraction of halved beats
removed, and behavior on the transitional runs that flipped the median. Also decide
**whether `rr_acceptance.dart` still needs a companion fix** (median anchoring) once
de-halving runs upstream, or whether de-halving alone makes the gate behave — this
decision gates whether note 30 is one entry or spawns a second.

## Guards

- Do not touch kit `lib/` or device code in this task — offline harness only.
- Do not introduce any constant ms/BPM threshold as the de-halving mechanism; the
  whole point is rate-proportional adaptation across 15–190 BPM.
- The two fixtures are resting-rate only (~68–70 BPM). Flag explicitly that the high
  end of the range is unvalidated offline and must be confirmed on device in note 31.

## Open Questions

- Can `FlutterPPGService` be reconfigured mid-stream (approach 2), or does it require a
  teardown/respawn per config change — and is that acceptable on the frame isolate?
- Does approach 1's period tracker converge fast enough from cold start, given the
  warm-up window already burns ~5 s?
