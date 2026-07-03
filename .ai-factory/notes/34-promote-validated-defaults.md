# Promote the validated tuning to the kit's committed defaults

**Date:** 2026-07-03
**Source:** conversation context (calibration handoff #1)

## Precondition

Note 31's human-in-the-loop re-calibration has run and **reported concrete validated
numbers** (the de-halving tracker params, and any `RrAcceptance`/`SessionPolicy` values
that changed, confirmed against a resting AND an elevated reference rate). This is the
orchestrator's follow-up: a pure code task that bakes those reported numbers in. Do not
start it until note 31 has produced the numbers — it has no values of its own to invent.

## Problem today

The tuning knobs still carry spike-provisional defaults borrowed from neiry's chest PPG
(`RrAcceptance` — `minRrMs`/`consistencyThreshold`/`coldStartBeats`/`medianWindow`,
`lib/src/processing/rr_acceptance.dart`; `SessionPolicy` — warm-up / SQI floor,
`lib/src/processing/session_policy.dart`; plus the de-halving tracker params introduced
by note 30). They are exposed as `[debug]` live knobs on the Source screen but the
committed **code defaults** are not yet the on-device-validated ones, so a host
integrating the kit gets untuned values.

## The change

Set the kit's committed internal default values to exactly the numbers note 31
validated — edit the default constructor values in `rr_acceptance.dart`,
`session_policy.dart`, and the note-30 de-halving stage. No new fields, no logic change,
no threshold that caps the 15–190 BPM range (that constraint is already enforced by
note 30's mechanism; this task only sets values). Record the final numbers and matrix
row in note 03. These are the values the API freeze (note 19 / Phase 10) will lock.

## Verify

- `flutter test` green — the note-30 fixture regression tests still pass with the new
  defaults (the resting fixtures must still land within counting error).
- The committed defaults equal the numbers note 31 reported; no `[debug]` override is
  needed to reproduce the validated result on a fresh Start.

## Guards

- Kit `lib/` values only — no new public surface (Phase-10 freeze, note 19); the
  `[debug]` live-knob plumbing stays as-is.
- Do not introduce any rate-capping constant here — if note 31 found the algorithm
  itself needs a change, that reopens note 29/30, it is not patched in as a default.
- No `done` state (note 23).

## Open Questions

- If note 31 could not validate the true high end (no reference source for ~190 BPM),
  commit the confirmed range's defaults and leave the extreme-high validation deferred
  to Phase 12 — do not guess the high-end numbers.
