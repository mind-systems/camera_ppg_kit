# Implement the adaptive de-halving stage

**Date:** 2026-07-03
**Source:** plan 23 (`.ai-factory/plans/23-de-halving-offline-design.md`) — offline
evaluation against both `.calibration/*.json` fixtures. See note 29's "Results"
section for the full evidence table this decision is based on.

## Decision

**Candidate 1 — RR-domain harmonic-pair merge** is the chosen approach. Scored
against the committed `RrAcceptance` baseline on both fixtures:

| | baseline (committed gate) | candidate 1 (harmonic merge) | candidate 2 (rate min-distance, offline approx.) |
|---|---|---|---|
| fixture 1 BPM error | +60.8 | **+0.8** | +35.8 |
| fixture 2 BPM error | +37.9 | **+4.9** | +24.9 |
| true-cluster retention | 10.7% / 58.2% | **100% / 100%** | 100% / 100% |
| halved-cluster removal | 0.8% / 10.7% | **98.8% / 98.4%** | 0.2% / 9.4% |
| transitional-run behavior | FLIPPED / FLIPPED | **held true / FLIPPED** (fixture 2 residual, see below) | FLIPPED / FLIPPED |

Candidate 1 is a decisive win: it turns a gate that *inverts* (accepts the
halved population, rejects true beats) into one that recovers the reference
rate to within counting error on the resting-rate fixtures. Candidate 2's
offline RR-domain approximation of a rate-derived floor could not be tuned
into a competitive result at any `floorFraction` swept (0.5/0.6/0.7 all left
either most halved beats un-caught or over-merged legitimate true beats into
inflated combined intervals) — see note 29's Results for the sweep. Candidate
3 (waveform-domain) was dismissed on feasibility grounds alone (no waveform
reaches the kit or the fixtures; see `test/dehalving/candidates/waveform_feasibility.md`).

Candidate 2 also carries materially higher implementation risk even setting
scoring aside: `flutter_ppg`'s `FlutterPPGService`/`PPGConfig` have no live
reconfiguration API (`PPGConfig` is `const`, `FlutterPPGService.config` is
`final`), so driving a rate-derived `minRRMs` would require tearing down and
respawning the service — and its `processImageStream`/`imageStreamCtrl`
subscription — on every tracked-rate change, inside the frame isolate. That
re-runs the close-before-cancel teardown ordering notes 07/13 already had to
get right once, but on a hot path (every rate adjustment) instead of once at
measurement end. Candidate 1 needs none of this — it is a pure RR-domain
stage with no isolate/teardown surface at all.

## Location and wiring

New file: **`lib/src/processing/rr_dehalving.dart`**, placed **before**
`RrAcceptance` in `CameraPpgSession._onSignal`
(`lib/src/api/camera_ppg_session.dart`):

```
signal.rrIntervals → diffNewIntervals → [new] RrDehalving.evaluate/flush → RrAcceptance.evaluate → rrStream
```

Concretely, in `_onSignal`'s RR-gating block (currently ~line 558-576): for
each `rr` in `newIntervals`, build the raw `candidate` `RrInterval` as today,
then run it through the new de-halving stage *before* `_acceptance.evaluate`.
Because the stage is 2:1 (buffering — see Output contract below), the
straight-line `for (final rr in newIntervals) { ...; add(evaluate(candidate)) }`
loop becomes: feed `candidate` to the de-halving stage, and only call
`_acceptance.evaluate(...)` + `_rrController.add(...)` for whatever the stage
actually returns (`null` most calls, an interval on others). `CameraPpgSession`
needs a new `_dehalving` field (constructor-injectable, mirroring `_policy`/
`_acceptance`, defaulting to a fresh instance) and must call `_dehalving.reset()`
alongside the existing `_acceptance.reset()` in `_release()` (same lifecycle
point — new measurement, re-arm cold start). No barrel export — this is
internal processing, like most of `_acceptance`'s type already is (only
`RrAcceptance` itself is a `[debug]` export per note 19; `RrDehalving` needs
no such exception unless a future milestone wants example-app live-tuning of
it too).

## Exact output contract

This is a **2:1 pair-merge, not the gate's 1:1 `evaluate`** — pinned exactly
as designed and tested in `test/dehalving/candidates/harmonic_merge.dart`
(`HarmonicMergeCandidate`), which is the reference implementation to port
into `lib/src/processing/rr_dehalving.dart`:

- **`RrInterval? evaluate(RrInterval rr)`** — returns `null` while a short
  interval is held pending a partner, or the next interval the stage has
  ready to emit otherwise (a merged pair, a beat proven standalone by what
  followed it, or a fresh full-length beat). Because a single input can
  occasionally resolve two ready outputs (a stale pending beat flushed by an
  unrelated following full beat), ready-but-unpopped output is buffered
  internally and drained on the *next* call — a `null`/non-`null` return does
  not always describe the interval just passed in. **Do not** assume
  byte-for-byte 1:1 parity with `RrAcceptance.evaluate`'s signature; the
  calling loop must be restructured (see Location and wiring above), not the
  stage's signature bent to fit the old loop.
- **`List<RrInterval> flush()`** — call once at end-of-stream (session stop),
  before `_acceptance.reset()`/teardown finishes; drains any buffered output
  plus a still-pending beat (emitted standalone — nothing ever arrived to
  prove or disprove it as half of a pair). In `CameraPpgSession`, the natural
  call site is `_release()`, right before `_acceptance.reset()` — though
  since a measurement's tail beats past the last `_onSignal` tick are, in
  practice, of low value once the session is stopping, `flush()`'s result can
  be discarded rather than piped to `_rrController` if that proves simpler;
  this is an implementation-detail call for the next milestone, not fixed by
  this note.
- **`void reset()`** — clears all state (tracker, bootstrap, pending,
  buffered output, decision log) for the next measurement.

## Algorithm and tracker params/defaults

Ported as-is from `HarmonicMergeCandidate` (`test/dehalving/candidates/harmonic_merge.dart`):

- **Bootstrap** (`bootstrapBeats = 3`, mirrors `RrAcceptance.coldStartBeats`):
  the median of the first 3 raw magnitudes seeds the tracked period
  unconditionally — no short/full classification or merging happens before
  this converges. Exposes `convergedAtBeatIndex` for diagnostics.
- **Short/full classification** (`shortFraction = 0.75`): a beat is a merge
  candidate when `rr.intervalMs < shortFraction * trackedPeriodMs` —
  proportional to the tracked rate, never a fixed ms floor.
- **Pairing** (`pairTolerance = 0.30`): two consecutive short beats merge
  when their sum is within 30% of the tracked period. A failed pairing
  flushes the stale pending beat standalone (untrusted — does not update the
  tracker) and starts fresh on the current beat.
- **Tracker update** (`trackerAlpha = 0.1` EMA): a successful merge always
  updates the tracker with the merged sum; a full-length beat updates it only
  when within `fullBeatTolerance = 0.40` of the current tracked period
  (guards the EMA against wild single-beat outliers).

These defaults were swept against both fixtures in `dehalving_eval_test.dart`
(see note 29 Results) and chosen for landing within ~5 BPM error on both
resting-rate fixtures — they are a starting point for the next milestone's
own unit tests, not necessarily final; the next milestone should keep them
tunable (constructor parameters, as today) rather than hardcoded, in case
on-device validation (note 31) shows they need adjustment across the wider
15–190 BPM range.

## Median-anchoring decision (Task 8 gate-interaction result)

**Mostly resolved, with a residual worth a companion fix — not automatically
folded into this entry.** Running the committed `RrAcceptance` *downstream*
of candidate 1's de-halving output:

- Fixture 1: 0 of 578 de-halved beats classified halved-cluster reached the
  gate as accepted (non-artifact) — the gate has nothing left to migrate
  onto; post-gate BPM error actually *improved* (0.8 → −0.2).
- Fixture 2: 1 of 478 de-halved beats classified halved-cluster still slipped
  past the gate as accepted; post-gate BPM error held roughly steady (4.9 →
  3.9).

Verdict: de-halving upstream overwhelmingly makes the gate behave — it is
**not** a prerequisite for shipping candidate 1 — but the one-beat residual
on fixture 2 means `rr_acceptance.dart`'s median-anchoring question is not
fully closed. **This is a separate, smaller follow-up entry** (not spawned as
a new note by this task; the next planning pass should decide whether it's
worth a dedicated milestone or just a note appended here once on-device data
(note 31) shows whether the residual matters in practice), per note 29's
original framing: "does `rr_acceptance.dart` still need median anchoring...
or does de-halving alone make the gate behave" — the answer is "de-halving
alone gets you most of the way; a small residual remains."

## High end of range — unvalidated offline

Both calibration fixtures are resting-rate only (68–70 BPM manual reference).
**Everything in this note and in `test/dehalving/` is validated only in that
band.** The full 15–190 BPM requirement (RR 316–4000 ms) — including whether
`shortFraction`/`pairTolerance`/`trackerAlpha` hold up at high HR, where the
true and halved clusters sit much closer together in absolute ms, and cold
start converges fast enough before warm-up ends — is **unvalidated and must
be confirmed on device**. This is note 31's job, not this one's: the next
milestone (implementing `rr_dehalving.dart`) should ship the algorithm above,
then note 31 validates it across the full range on real hardware before it's
considered done.

## Verify (for the implementing milestone)

- Unit tests replay both `.calibration/*.json` fixtures (as test assets,
  copied the same way `test/dehalving/fixtures/` already does — or reuse
  those files directly) and assert the derived BPM lands within counting
  error of each file's `manualCount`, with true-cluster beats retained and
  the halved cluster removed — the same scoring `test/dehalving/scoring.dart`
  used, now as regression tests. The existing `test/dehalving/` harness can
  likely be adapted/reused rather than rewritten from scratch.
- Public streams (`rrStream`/`qualityStream`/`stateStream`) unchanged in
  shape; `flutter test` green.
- On-device confirmation is note 31, not here.

## Guards

- Do not weaken `RrAcceptance`'s physiological floor into a de-halving hack —
  halving is a harmonic problem, solved by the period tracker, not by a
  threshold. This was validated: `shortFraction`/`pairTolerance` are
  proportional to the tracked rate throughout, never a fixed ms/BPM constant
  (plan 23's Constraints).
- Keep the frame-isolate teardown invariant intact (close input bridge before
  cancelling the subscription — notes 07/13); `rr_dehalving.dart` itself
  never touches isolate/camera code (pure `src/processing/`, per
  `ARCHITECTURE.md`'s dependency rule), so this only matters for wiring
  `flush()`/`reset()` into `CameraPpgSession`'s existing teardown sequence
  correctly, not for the stage's own internals.
- No barrel export changes; this is internal processing, not public API.
