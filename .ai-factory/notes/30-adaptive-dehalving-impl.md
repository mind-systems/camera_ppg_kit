# Implement the adaptive de-halving stage

**Date:** 2026-07-03
**Source:** conversation context (calibration handoff #1)

## Precondition

Note 29 has run and chosen ONE adaptive de-halving approach with offline evidence
against both `.calibration/*.json` fixtures. This task implements exactly that chosen
approach; its precise file/type shape is fixed by note 29's decision. Do not start this
until note 29 names the approach.

## Current state

`CameraPpgSession` bridges `flutter_ppg` output to kit models at the edge
(`lib/src/api/camera_ppg_session.dart` `_onSignal` → `diffNewIntervals` →
`RrAcceptance.evaluate`). The frame path runs off-UI in the isolate
(`lib/src/processing/frame_isolate.dart`, `FlutterPPGService(config: const
PPGConfig())` at line ~231). The acceptance gate (`rr_acceptance.dart`) is the only
kit-added processing stage today, and it has no de-halving — it assumes the interval
stream already reflects one beat per pulse.

## The change

Add the chosen adaptive de-halving mechanism as a pure, unit-tested stage:

- **If note 29 picks RR-domain harmonic merge:** new
  `lib/src/processing/rr_dehalving.dart` — a stateful, one-instance-per-measurement
  filter that tracks the fundamental beat period (per note 29's tracker) and merges
  harmonic pairs, placed **before** `RrAcceptance` in `_onSignal` so the gate's rolling
  median only ever sees de-halved beats. Mirror `RrAcceptance`'s shape: `evaluate(...)`
  per interval in order, `reset()` between measurements. No `flutter_ppg`/`camera` type
  crosses it. Export nothing new from the barrel (internal processing).
- **If note 29 picks driving `PPGConfig` peak params:** thread a live-updatable
  `minRRMs` (derived from the tracked BPM, not a constant) into the `FlutterPPGService`
  the frame isolate owns, plus whatever control message the isolate protocol needs to
  reconfigure mid-stream. The derived value must scale with the tracked rate so it
  never caps 15–190 BPM.

Rate-proportional only — **no constant ms or BPM floor** may be the mechanism. If note
29 also found the gate needs median anchoring, that is a *separate* entry, not folded
in here.

## Verify

- Unit tests replay both `.calibration/*.json` fixtures (as test assets) and assert the
  derived BPM lands within counting error of each file's `manualCount`, with the
  true-cluster beats retained and the halved cluster removed — the same scoring note 29
  used, now as regression tests.
- Public streams (`rrStream`/`qualityStream`/`stateStream`) unchanged in shape;
  `flutter test` green.
- On-device confirmation is note 31, not here.

## Guards

- Do not weaken `RrAcceptance`'s physiological floor into a de-halving hack — halving is
  a harmonic problem, solved by the period tracker, not by a threshold.
- Keep the frame-isolate teardown invariant intact (close input bridge before
  cancelling the subscription — notes 07/13) if the isolate path is touched.
- No barrel export changes; this is internal processing, not public API.

## Open Questions

- Resolved by note 29 (approach, tracker, whether a companion gate fix is needed).
