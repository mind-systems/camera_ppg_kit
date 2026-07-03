# Candidate 3 — waveform-domain fundamental estimation: feasibility assessment

Plan 23 / spec note 29, Task 6. **Feasibility only — no runnable code.** This
candidate is dismissed on record here so note 30's decision can cite it
rather than silently drop it.

## What the approach would do

Autocorrelation or FFT of the filtered PPG waveform (the intensity signal
`flutter_ppg`'s `SignalProcessor` bandpass-filters before peak detection)
to find the true fundamental frequency directly, then reject or re-time
peaks that fall off that fundamental — solving de-halving at the signal
level rather than after RR intervals have already been extracted.

## Why it is unreachable offline

- The two `.calibration/*.json` fixtures this harness replays (per plan
  23's Constraints: "Fixtures are RR-only") carry only
  `intervals[]` (`{tMs, rrMs, isArtifact, sqi}`) — beat-level RR data, not
  the raw or filtered intensity waveform. There is no signal here to run
  autocorrelation or an FFT against.
- `flutter_ppg`'s `FlutterPPGService` consumes the waveform entirely
  internally: `SignalProcessor` extracts and filters intensity from
  `CameraImage` frames into private ring buffers
  (`_rawBuffer`/`_filteredBuffer` in `flutter_ppg_service.dart`), and
  `PeakDetector` runs on that filtered buffer — none of it is exposed on
  `PPGSignal` (the package's public output type only carries `rrIntervals`,
  `snr`, `rawIntensity`/`filteredIntensity` as **scalar per-frame
  values**, not the buffered window a fundamental-estimation algorithm
  would need).
- Recording a raw/filtered waveform fixture is not just "not done yet" —
  the current calibration capture path (`.calibration/*.json`, written from
  `CameraPpgSession`) only ever sees the same `PPGSignal` scalars the kit
  already exposes, so no waveform reaches the app layer to capture in the
  first place. Getting one would require patching `flutter_ppg` itself to
  expose its internal buffers, or forking it to run the fundamental
  estimation inside the package.

## Verdict

**Out of scope for this kit unless `flutter_ppg` is forked.** Neither the
existing fixtures nor the existing kit-to-`flutter_ppg` integration surface
carries the waveform this approach needs, and closing that gap is a
`flutter_ppg`-level change, not something `camera_ppg_kit`'s own processing
layer can add. Candidates 1 and 2 (Tasks 4–5) both operate on data the kit
already has (the RR stream); candidate 3 does not, and is dismissed from
the note 30 decision on that basis.
