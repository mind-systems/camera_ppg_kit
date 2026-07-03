# Code Review: Adaptive de-halving stage (task 24) — review 1

## Scope
- `lib/src/processing/rr_dehalving.dart` (new) — read in full
- `lib/src/api/camera_ppg_session.dart` (modified) — diff + surrounding `_onSignal`/`_release`/constructor read in full
- `test/processing/rr_dehalving_test.dart` (new) — read in full
- Cross-checked against reference `test/dehalving/candidates/harmonic_merge.dart`, spec note 30, `ARCHITECTURE.md`, the barrel, and the example app's constructor usages.

## Verification performed
- `flutter test test/processing/rr_dehalving_test.dart` → **9/9 pass**.
- `flutter test` (full suite) → **64/64 pass**, including the untouched `diffNewIntervals` and the offline `dehalving_eval_test.dart` gate-interaction harness.
- `flutter analyze lib/ test/` → **No issues found**.

## Correctness assessment

**Port fidelity (rr_dehalving.dart).** The algorithm is a faithful, verbatim port of `HarmonicMergeCandidate`: bootstrap median seed, `shortFraction` classification, `pairTolerance` merge, `trackerAlpha` EMA on merges and on full beats within `fullBeatTolerance`, the `Queue`-backed buffering contract, and `flush()`/`reset()`. Defaults match note 30 exactly (3 / 0.75 / 0.30 / 0.1 / 0.40) and remain constructor parameters, leaving note 34 free to promote validated values without a signature change. The offline-scoring scaffolding (`BeatOutcome`/`_decisions`/`outcomes`) is correctly dropped, and the `convergedAtBeatIndex` source is preserved via the standalone `_beatIndex` counter (incremented in `evaluate`, zeroed in `reset`) exactly as the plan's porting-hazard note required — verified green by the bootstrap mechanics test asserting index `2`.

**Buffer growth is bounded.** Each `evaluate` removes at most one queued item; the only path that enqueues two (`_handleFull` while a beat is pending) is self-limiting because it clears the pending. Steady state keeps the queue ≤1, so there is no unbounded accumulation over a long session — the memory concern that motivated dropping `_decisions` does not reappear elsewhere.

**Dependency rule.** The stage imports only `dart:collection` and `../models/rr_interval.dart` — honors ARCHITECTURE's `src/processing/ → src/models/ only` rule. No barrel export added; `RrDehalving` stays internal (unlike the `[debug]` `RrAcceptance`/`SessionPolicy`), matching note 30.

**Wiring (`_onSignal`).** The loop restructure is correct and matches the plan precisely:
- Every trusted `candidate` is fed to `_dehalving.evaluate(...)` **unconditionally**; the `_rrController.isClosed` guard was correctly moved off the feed and onto the terminal `add`, so a teardown-race tick can no longer corrupt the stage's pending/pair state.
- `null` outputs `continue` (held pending); non-null outputs flow through `_acceptance.evaluate(...)` → `_rrController.add(...)`. The gate's rolling median now only ever sees de-halved beats — the exact intent of note 30, confirmed by the offline gate-interaction harness (fixture 1: 0 halved beats reach the gate; fixture 2: 1 residual, the known follow-up).

**Lifecycle (`_release`).** `_dehalving.reset()` is placed alongside `_acceptance.reset()`, re-arming cold start per measurement. `flush()` is correctly **not** called here (it would be a no-op before `reset()` and risks a future "fix" piping tail beats into a tearing-down controller) — matches the plan's Task 4 decision.

**Backward compatibility.** The new `RrDehalving? dehalving` constructor param is optional; the example app's `CameraPpgSession(policy:, acceptance:)` and `CameraPpgSession()` call sites compile unchanged. The unexported param type is fine (consumers omit it).

**Physiological floor still holds.** Merges only fire when a pair sums to within `pairTolerance` of the tracked period, so sub-threshold noise (e.g. 150+150) does not merge — it flushes standalone and is caught by `RrAcceptance`'s 300 ms floor / consistency check downstream. The de-halver does not weaken the floor into a rate cap; classification is proportional throughout.

**Test quality.** The mechanics cases exercise bootstrap convergence, merge (with timestamp propagation), failed-pair standalone flush without tracker pollution, out-of-tolerance full beat, pending flush, and reset — all trace correctly against the algorithm. The fixture regression drives the shipped `RrDehalving` directly and asserts BPM within the correct `_countingErrorBpm + 2` (≤5) tolerance — the plan-review-1 fix that avoids the fixture-2 ≈+4.9 false failure. I specifically suspected the secondary output-classification thresholds (true ≥0.7, halved ≤0.05) might be fragile since they measure a different metric than the offline harness's input-outcome fractions; running the suite confirmed they pass on both fixtures.

## Non-blocking observation (no action required)
Because `_dehalving.evaluate` is only reached inside `if (_policy.rrTrusted)`, a `poorSignal` gap can leave a short beat parked in `_pending` and later bridge it to the first beat after the gap. This is benign: if the resuming beat is full, the stale short is flushed standalone and `RrAcceptance`'s >40%-deviation check flags it as an artifact; if it is short, the two halved beats merge into a plausible period-length interval. Either way the output is downstream-guarded and matches the accepted design (note 30 explicitly treats tail beats as low-value and relies on the gate for residuals). No change warranted.

## Conclusion
No correctness, security, or runtime defects found. The implementation matches the plan and note 30, all tests and the analyzer are green.

REVIEW_PASS
