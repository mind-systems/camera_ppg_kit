# Re-calibrate on device and confirm across the HR range

**Date:** 2026-07-03
**Source:** conversation context (calibration handoff #1)

## Precondition

Note 30's adaptive de-halving is implemented and green on the offline fixtures. This is
a **human-in-the-loop** task (needs the tester's finger — it is the reason the STOP
marker exists): prove the fix holds on real hardware across the pulse range and report
the validated numbers. It writes **no code**. Committing those numbers as the kit's
internal defaults is the orchestrator's follow-up, note 34, gated on this task's output.

## Current state

Two resting-rate fixtures exist (~68–70 BPM). The offline harness only validates the
low end; the 15–190 BPM constraint is unproven on device, and the halved cluster is
numerically indistinguishable from a genuine high pulse, so the high end is where an
over-eager de-halver would fail (merging real fast beats).

## The change

- Re-record calibration runs on device using the Calibration screen (note 21) at **two
  reference rates**: a resting run and an elevated run (post-exertion — as high as the
  tester can reach; 190 BPM need not be hit, but a clearly-elevated rate must be, to
  probe the merge's high-end safety). Manual beat count per run remains the reference.
- Confirm the kit's derived BPM tracks each manual count within counting error, and
  that the elevated run is **not** over-merged down toward the resting rate.
- Once confirmed, promote the validated tuning (the de-halving tracker params, and any
  `RrAcceptance`/`SessionPolicy` values that changed) from spike-tunable defaults to the
  kit's committed internal defaults — the numbers the API freeze (note 19 / Phase 10)
  will lock. Record the final matrix row and numbers in note 03 / this note.

## Verify

- Both new runs: |kit BPM − manual BPM| within counting error at rest AND when
  elevated.
- Saved calibration JSONs added to `.calibration/` and referenced here as evidence.
- No regression in SQI/finger-presence gating during the elevated run.

## Guards

- Do not re-introduce a rate cap to "stabilize" the elevated run — if the merge
  over-collapses a real fast pulse, that is a note-29/30 defect to fix at the tracker,
  not to paper over with a threshold.
- This is the STOP-marker handoff task: it needs the tester's finger and a way to
  elevate the pulse; it cannot be completed head-down by the orchestrator alone.

## Open Questions

- Can the tester reach a high enough rate on demand, or is a second reference source
  (the Phase-12 oximeter path) needed to validate the true high end? If the latter,
  note that limitation and defer the extreme-high validation there.
