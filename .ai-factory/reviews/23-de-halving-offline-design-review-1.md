# Code Review — De-halving offline design (plan 23)

**Scope reviewed:** the code changes under `test/dehalving/` (`fixture.dart`, `scoring.dart`, `baseline.dart`, `candidates/harmonic_merge.dart`, `candidates/rate_min_distance.dart`, `dehalving_eval_test.dart`), plus the design deliverables (`notes/29`, `notes/30`, `candidates/waveform_feasibility.md`) that the harness backs. Read each file in full against the kit's `RrInterval`/`RrAcceptance` and both `.calibration/*.json` fixtures.

**Verification performed (not just reading):**
- `flutter analyze test/dehalving/` → **No issues found**.
- `flutter test test/dehalving/dehalving_eval_test.dart` → **all tests pass**; captured the full printed evidence table.
- Instrumented a throwaway replay to check the Task-3 oracle-validity claim on both fixtures and to locate the fixture-2 divergence.

**Risk level:** 🟢 Low. The harness compiles clean, runs green, and — importantly — the numbers it prints match note 29's Results table exactly (BPM 131/71/106 on fixture 1, 106/73/93 on fixture 2; retention/removal; the gate-interaction 0-vs-1 residual). The design conclusion (candidate 1 wins; `rr_acceptance.dart` gets a small follow-up, not a co-requisite) is supported by the evidence as recorded. Candidate scoring is driven by `manualCount`/`referenceBpm` and each candidate's own re-derivation, so it is independent of the fixture-2 gate-replay gap below.

---

## Findings

### 1. (Low, non-blocking) The harness never asserts the oracle-validity precondition it computes — even fixture 1's clean reproduction is unguarded

`baseline.dart` computes `matchingArtifactFlags` and exposes `BaselineResult.reproducesRecordedFlags` — the whole point of Task 3 is that a fixture is only a trustworthy candidate oracle if the committed `RrAcceptance` reproduces its recorded `isArtifact` flags. But no test asserts it. `dehalving_eval_test.dart` calls `runBaseline(fixture)` only to `print` its score (`_printRow`), and its one `expect` guards candidate 1's BPM error, not the baseline. Because this file lives under `test/` it runs on every `flutter test`, so it is a permanent test that silently tolerates:

- **Fixture 2 not reproducing:** I verified the replay yields **590/645** matching flags (91.5%), `derivedBpm=106` (not the recorded `kitBpm=112`), `472` accepted vs recorded `431`. The 55 mismatches are all in the first ~56 rows (`tMs ≲ 5.3 s`, the warm-up window) — every one is a beat the on-device pipeline flagged `isArtifact=true` that the standalone gate accepts. Fixture 1 reproduces exactly (868/868, BPM 131) through the same code, so this is intrinsic to fixture 2, not a replay bug. **note 29's Results section documents this accurately and honestly** (lines 89–105) and correctly argues it does not undermine the de-halving scoring — so this is not a hidden defect, just an unenforced check.
- **A future regression going unnoticed:** if someone later edits `RrAcceptance`, `toRrIntervals`, or a fixture, the loss of fixture 1's 868/868 reproduction would not fail the suite.

Recommendation (non-blocking, harness quality): add an explicit `expect` that fixture 1 reproduces (`baseline.reproducesRecordedFlags == true`, or `matchingArtifactFlags == totalBeats`), and for fixture 2 assert the *documented* partial figure (e.g. `matchingArtifactFlags >= 589` / mismatches confined to the warm-up prefix) rather than leaving the precondition entirely unchecked. This makes the code enforce exactly what note 29 asserts in prose.

---

## Non-issues checked and cleared

- **BPM derivation** is mean-of-magnitudes (`round(60000 / mean(accepted))`) everywhere (`scoring.dart:177-179`, eval `:145`); the earlier median cross-check that would have mis-derived 144 on fixture 1 is correctly gone. Reproduces fixture 1's `kitBpm=131`.
- **Harmonic-merge buffering contract** is sound: `_outQueue` (FIFO) can hold a leftover across an `evaluate` call and drains it in order on the next call / at `flush()`; a `null` return strictly means "nothing ready". Verified all original beats resolve (the `outcomes` getter's no-`null` assert holds after `flush()`), and `runHarmonicMerge` always flushes. Accepted-magnitude order and count are correct for the mean.
- **`shortFraction`/`floorFraction`/`pairTolerance` are all proportional to the tracked period** — no fixed ms/BPM floor is introduced anywhere, honoring the roadmap's central constraint (the `minRrMs` inside `RrAcceptance` is the *committed gate's* existing floor, used read-only for baseline replay, not a new de-halving threshold).
- **`toRrIntervals()` synthesizes the required `timestamp`** (`DateTime.fromMillisecondsSinceEpoch(tMs)`); the gate reads only `intervalMs`, so this is safe and compiles.
- **Candidate 2 feasibility record** matches the actual `flutter_ppg` 0.2.4 / `frame_isolate.dart` reality (config is a `final PPGConfig`, adaptivity keyed on FPS, mid-stream reconfig needs teardown/respawn). Correctly scoped as part-measured/part-feasibility; candidate 3 correctly dismissed as waveform-unavailable.
- **Loader path resolution** uses `Directory.current` (package root under `flutter test`), not `Platform.script`, as the plan required; fixtures are self-contained under `test/dehalving/fixtures/`.
- **Soft assertion margin** (`bpmError.abs() <= 5`, fixture 2 is 4.9) is intentional and commented; note 29 honestly records candidate 1's fixture-2 error as +4.9 (outside the ±3 target), not glossed.
- **Transitional-run probe** flips to `FLIPPED` on a single leaked standalone halved beat (candidate 1 / fixture 2, 98.4% removal, reads as FLIPPED) — slightly pessimistic but disclosed in note 29 as "residual"; not a correctness defect.
- **No security surface.** Test-only, offline, reads two bundled JSON files; no `lib/`, device, or network changes (roadmap guard respected).

The one finding above is advisory and does not block; the produced evidence and the decision it supports are correct.
