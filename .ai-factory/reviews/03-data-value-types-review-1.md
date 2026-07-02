# Code Review: 03 — Data value types

**Plan:** `.ai-factory/plans/03-data-value-types.md`
**Files reviewed (in full):** `lib/src/models/rr_interval.dart`, `lib/src/models/signal_quality.dart`, `lib/camera_ppg_kit.dart`, `test/models_test.dart`; cross-referenced `neiry_kit/lib/src/models/rr_interval.dart` and `flutter_ppg-0.2.4` (`ppg_config.dart`, `quality_assessor.dart`).

## Summary

The implementation is clean and matches the plan: `RrInterval` is shape-identical to neiry's type (correct field names/defaults, `@immutable`, docs ported), the barrel exports both models without disturbing the scaffold, and the tests cover construction, defaults, both threshold boundaries, and degenerate SNR. It compiles conceptually and the tests as written pass against the implementation.

One real correctness finding around the `fromSnr` boundary semantics, plus a documentation-accuracy issue tied to it.

## Findings

### 1. (Medium) `fromSnr` boundary is inclusive `>=`, disagreeing with flutter_ppg's strict `>` — and the reachable `SNR == 0.0` sentinel is misclassified as `fair`

`lib/src/models/signal_quality.dart:39-44` classifies with inclusive lower bounds:

```dart
if (snr >= _goodSnrThreshold) return SignalQuality.good;  // 5.0
if (snr >= _fairSnrThreshold) return SignalQuality.fair;  // 0.0
return SignalQuality.poor;
```

flutter_ppg's own `SignalQualityAssessor.assessQuality` (`quality_assessor.dart:97-99`) uses **strict** `>`:

```dart
if (snr > minGoodSNR) return SignalQuality.good;
if (snr > minFairSNR) return SignalQuality.fair;
return SignalQuality.poor;
```

The doc comment on the constants claims the values are "mirrored from `flutter_ppg`'s own `PPGConfig.minGoodSNR`/`minFairSNR`", implying behavioral fidelity — but the boundary inclusivity is inverted, so the two classifiers disagree at exactly the threshold values.

This is not purely theoretical because `SNR == 0.0` is a **reachable, non-rare sentinel**, not a measure-zero float coincidence. `calculateSNR` (`quality_assessor.dart:52-70`) returns exactly `0.0` in two cases: a signal window shorter than 2 samples, and a flat signal (`signalVariance == 0`, "Flatline"). At `snr == 0.0`:

- flutter_ppg → `0.0 > 0.0` is false twice → **poor** (correct: flatline / no data is a bad signal).
- kit `fromSnr` → `0.0 >= 0.0` (good) false, `0.0 >= 0.0` (fair) **true** → **fair**.

So when this factory is wired to flutter_ppg's SNR in the Phase-4 API layer, a flatline / insufficient-data window will be reported to the host as `fair` instead of `poor` — the opposite of the intent, and it contradicts the same file's own reasoning that "negative SNR ... always yield[s] poor" (a no-signal state landing in `fair` while a slightly-negative one lands in `poor` is incoherent). Note also flutter_ppg asserts `minGoodSNR > minFairSNR` (strict), consistent with its `>` usage.

**Recommendation:** use strict `>` to match flutter_ppg (making `0.0` → `poor`), or raise `_fairSnrThreshold` above `0.0`. Then update `test/models_test.dart` — the test `returns fair at and above the fair threshold (0.0, inclusive)` currently pins the `>=` behavior and asserts `fromSnr(0.0) == fair`; it must be changed to expect `poor` at `0.0`. Also correct the boundary doc comment (`signal_quality.dart:33-40`) to stop claiming it mirrors flutter_ppg while using different inclusivity.

If the team deliberately wants `>=` for the kit's own contract (independent of flutter_ppg), that is defensible — but then the "mirrored from flutter_ppg" doc claim should be dropped and the `SNR == 0.0` → `fair` outcome should be an explicit, intentional decision rather than an accident of boundary choice.

## Non-blocking notes

- **`RrInterval` — correct.** Field names (`intervalMs`/`timestamp`/`isArtifact`), `const` ctor, `isArtifact = false` default, `@immutable`, and the ported doc comments all match neiry's `RRInterval` exactly. No BPM/HRV/quality fields. The load-bearing shape constraint is satisfied.
- **Barrel — correct.** Only the two models are exported; nothing from `channel`/`processing`/`util`; the `CameraPpgKit` scaffold is intact.
- **No value-equality / `hashCode`.** `RrInterval` is `@immutable` but has no `==`/`hashCode` override (matches neiry, so cross-kit-consistent). Fine for a stream-emitted value; only note it in case a later phase compares intervals by value or dedupes them.
- **`SignalQuality` drops the numeric SNR.** As the plan review already noted, later phases that need to gate on the raw SNR value (not just the band) will have to source it separately. Within spec for this task.

## Verdict

Findings above should be addressed (Finding 1 changes behavior at a reachable input and requires a corresponding test change). Not REVIEW_PASS.
