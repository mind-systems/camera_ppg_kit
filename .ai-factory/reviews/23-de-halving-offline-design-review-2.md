# Code Review (pass 2) — De-halving offline design (plan 23)

**Scope:** re-review of the code changes under `test/dehalving/` after the harness was updated in response to review-1. Ran `git status`/`git diff HEAD`. Read all `test/dehalving/` code in full (loader, scoring, baseline, both candidates, eval test) plus the design deliverables (`notes/29`, `notes/30`, `candidates/waveform_feasibility.md`). On this invocation the tree is unchanged from the prior pass-2 (identical file mtimes, empty unstaged `git diff`) and still green.

**Verification performed (not just reading):**
- `flutter analyze test/dehalving/` → **No issues found**.
- `flutter test test/dehalving/` → **3 tests pass** (evaluation, oracle-validity, gate-interaction). Printed evidence matches note 29's Results table exactly (131/71/106 and 106/73/93; retention/removal; gate residual 0 vs 1).
- Earlier this session, instrumented a throwaway probe confirming the fixture-2 assertion's headroom: `matchingArtifactFlags=590` (threshold ≥589), `lastMismatchTMs=5292` vs bound `warmupMs+1000=6000`.

**Risk level:** 🟢 Low — clean.

## Review-1 finding — resolved

Review-1's sole finding (the Task-3 oracle-validity precondition was computed but never asserted) has been correctly addressed:

- New test **`Task 3 oracle-validity precondition: fixture reproduction is enforced`** asserts fixture 1 reproduces exactly (`reproducesRecordedFlags == true`, i.e. 868/868) and fixture 2 meets its documented partial figure (`matchingArtifactFlags >= 589`) with mismatches confined to the warm-up-adjacent prefix (`lastMismatchTMs <= warmupMs + 1000`).
- `baseline.dart` gained `lastMismatchTMs` to support the confinement check; `fixture.dart` gained a parsed `FixturePolicy` (`warmupMs`/`silenceMs`/`sqiFloor`) so the bound is derived from the fixture header, not hardcoded. Both fixtures carry the `policy` block, so parsing is safe.
- The `else { fail(...) }` branch also guards against a future third fixture being scored without an explicit oracle-validity expectation — a good defensive touch.

The enforcement now matches exactly what note 29's Results section claims in prose, and would catch a regression in `RrAcceptance`, `toRrIntervals`, or the fixtures. Verified headroom is real (not razor-thin): fixture-2 last mismatch is 5292 ms against a 6000 ms bound.

## Points checked and cleared this pass

- **No type/parse risk from `FixturePolicy`.** `warmupMs`/`silenceMs` parse as `int`, `sqiFloor` as `String`; present in both bundled fixtures. `CalibrationFixture`'s required `policy` field is populated in the single `fromJson`, so no construction path is left unset.
- **The 589 threshold is intentionally tight (actual 590)** — one margin — but that is the point of the guard ("guard against it widening"), and it is a documented figure, not an arbitrary bound. Acceptable.
- **Candidate algorithms correct** — re-verified the harmonic-merge FIFO buffering contract (all input beats resolve before the `outcomes` no-`null` assert; `flush()` always called; merged pairs emit exactly one magnitude), rate-proportional thresholds (no fixed ms/BPM floor anywhere), and mean-of-magnitudes BPM derivation.
- **Soft assertion `bpmError.abs() <= 5`** (fixture 2 is 4.9) is intentional and commented; note 29 honestly records the +4.9 as outside the ±3 target.
- **Design deliverables consistent with the harness** — note 29 Results, note 30 decision, and `waveform_feasibility.md` all match the numbers the suite actually prints; fixture-2's non-exact reproduction is disclosed, not hidden.
- **No security surface** — test-only, offline, reads two bundled JSON files; no `lib/`/device/network changes (roadmap guard respected).

No outstanding issues.

REVIEW_PASS
