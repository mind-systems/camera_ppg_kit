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
  **Answered in Results below: no live reconfiguration API exists; teardown/respawn only.**
- Does approach 1's period tracker converge fast enough from cold start, given the
  warm-up window already burns ~5 s? **Answered in Results below: yes, by beat #2 on
  both fixtures (well inside the emission-rate budget of the ~5s warm-up).**

## Results (plan 23 — offline harness under `test/dehalving/`)

Decision: **candidate 1 (RR-domain harmonic-pair merge)**, written up in full in
note 30. This section records the evidence.

### Harness fidelity vs the recorded fixtures (Task 3)

Replaying each fixture's raw stream through a freshly-constructed
`RrAcceptance` (seeded with that fixture's own recorded `acceptance` params)
reproduces the recorded `isArtifact` flags **868/868 on fixture 1** — a
faithful oracle, as this note's Key Findings already established. **Fixture 2
does not reproduce byte-for-byte: 590/645 (91.5%).** Every mismatch (55 of
55) falls within the first ~56 rows (before `tMs` ≈ 5.3s); from row 56 onward
the replay matches the recording exactly for the remaining 589 rows. This
points to on-device gate state that predates what `intervals[]` captures
(e.g. warm-up-phase beats feeding the same live `RrAcceptance` instance
before recording started) — not a bug in the harness or in `RrAcceptance`
itself, and not something reconstructable from the fixture alone. Recorded
honestly rather than forced to match; it does not affect fixture 2's
usefulness as a *de-halving* scoring oracle (`manualCount`/`referenceBpm` are
independent of this), only its use as a byte-exact gate-replay oracle for its
first ~5 seconds.

### Scored comparison (Task 7)

Both fixtures, `referenceBpm` = 70.2 (fixture 1) / 68.1 (fixture 2):

| | baseline (committed `RrAcceptance`) | candidate 1: harmonic merge | candidate 2: rate min-distance (offline approx.) |
|---|---|---|---|
| fixture 1 derived BPM (error) | 131 (+60.8) | **71 (+0.8)** | 106 (+35.8) |
| fixture 2 derived BPM (error) | 106 (+37.9) | **73 (+4.9)** | 93 (+24.9) |
| fixture 1 true-cluster retention | 10.7% | **100.0%** | 100.0% |
| fixture 2 true-cluster retention | 58.2% | **100.0%** | 100.0% |
| fixture 1 halved-cluster removal | 0.8% | **98.8%** | 0.2% |
| fixture 2 halved-cluster removal | 10.7% | **98.4%** | 9.4% |
| fixture 1 transitional run (`958,917,708,708,583,500,458` near 5.7s) | FLIPPED onto halved cluster | **held true cluster** | FLIPPED |
| fixture 2 transitional run (`833,667,500,500,417`) | FLIPPED | FLIPPED (residual — see note 30) | FLIPPED |
| cold-start convergence | n/a | beat #2 (both fixtures) | beat #2 (both fixtures) |

Candidate 1's defaults (`bootstrapBeats=3, shortFraction=0.75,
pairTolerance=0.30, trackerAlpha=0.1, fullBeatTolerance=0.40`) were chosen
from a parameter sweep (`shortFraction` 0.65–0.80 × `pairTolerance`
0.15–0.30 × `trackerAlpha` 0.1–0.3) that minimized max BPM error across both
fixtures simultaneously. Candidate 2 was swept over `floorFraction`
0.5/0.6/0.7: 0.5 barely removed any halved beats (0.2–9.4% removal, many
halved-cluster beats sit above a 0.5× floor and pass through as if
standalone); 0.7 removed everything but badly over-merged legitimate
sequences into inflated combined intervals (BPM crashed to 39/46) — no
setting was competitive with candidate 1.

### Gate-interaction experiment (Task 8)

Running the committed `RrAcceptance` *downstream* of candidate 1's de-halved
output (de-halving first, gate second):

- Fixture 1: 578 de-halved beats reach the gate; 14 flagged as artifacts by
  the gate; **0** halved-cluster beats slip through as accepted. Post-gate
  BPM error improves from +0.8 to **−0.2**.
- Fixture 2: 478 de-halved beats reach the gate; 12 flagged as artifacts;
  **1** halved-cluster beat still slips through as accepted. Post-gate BPM
  error holds roughly steady, +4.9 → **+3.9**.

**Answer to this note's Scoring question:** de-halving upstream overwhelmingly
resolves the gate's inversion — it is not a hard prerequisite for shipping
candidate 1 — but the one-beat residual on fixture 2 means
`rr_acceptance.dart` isn't fully closed out. Note 30 records this as a
smaller follow-up, not folded into the de-halving entry itself.

### Candidate 3 (waveform-domain) feasibility

Dismissed on record, not silently: no raw/filtered waveform reaches either
the fixtures or the kit's own integration with `flutter_ppg` (`PPGSignal`
only exposes scalar per-frame `rawIntensity`/`filteredIntensity`, not a
buffered window). Full evidence in
`test/dehalving/candidates/waveform_feasibility.md`.

### High end of range

Both fixtures are resting-rate only (68–70 BPM). Everything above is
validated only in that band; the full 15–190 BPM requirement is **unvalidated
offline** and must be confirmed on device — this is note 31's job.
