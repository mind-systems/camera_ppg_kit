# RR Acceptance Gate (port from neiry)

**Date:** 2026-06-21
**Source:** `neiry_kit/lib/src/processing/ppg_peak_detector.dart` (`_gate()` semantics only); ROADMAP Phase 8; note 05 (`RrInterval` model); ARCHITECTURE.md (`src/processing/` purity rule)

## Key Findings

- `flutter_ppg` **already does the peak detection** and emits bounded RR intervals (300–2000 ms via `PPGConfig`). So this task ports **only** neiry's `_gate()` artifact logic — never neiry's `_findPeaks()`, buffer, refractory, or adaptive-PPI machinery. Those concerns belong to `flutter_ppg` here.
- The gate is **per-beat validity only**: it sets `RrInterval.isArtifact` (note 05). It does **not** decide session state (warm-up / poorSignal / done) — that is note 09. Keep the two concerns strictly separate; this gate never discards a beat, it only flags it.
- It is **stateful across beats** (rolling median history). It must expose `reset()` for after a measurement stops, mirroring neiry's reset-after-silence contract so the cold-start grace re-seeds on the next measurement.
- Pitfall: `flutter_ppg`'s `PPGConfig` may already clamp at 300–2000 ms, but **do not rely on it** — re-apply the hard lower bound and explicitly apply **no** upper bound (extreme bradycardia is real; >2000 ms intervals must survive the gate even if flutter_ppg's own bound differs).
- **Thresholds are injectable, defaulted, and out of the freeze.** The four ctor params keep internal defaults (below); they reach the example via an optional `[debug]` `RrAcceptanceConfig` on `CameraPpgSession` (note 07), so the playground can tune them **live** during the Phase 2/8 spike — these are *not* host config (note 19: the host never tunes "40% consistency"). We do not yet know the right values for camera PPG (neiry's come from chest PPG), so live tuning is the point. After the spike, good numbers become the **new internal defaults** here; the ctor path survives only for tests/re-tuning and never enters the consumer freeze (note 19).

## Details

### `lib/src/processing/rr_acceptance.dart` (new file)

Pure Dart. Imports **only** `../models/rr_interval.dart`. Zero Flutter / `camera` / `flutter_ppg` / channel imports — isolate-safe and unit-testable per ARCHITECTURE.md rule 4. Not exported from the barrel (internal `src/processing/`).

A stateful class `RrAcceptance` with constructor params copied from neiry's gate fields:
- `minRrMs = 300` — hard lower bound; `intervalMs < minRrMs → artifact`.
- `consistencyThreshold = 0.40` — >40% deviation from rolling median → artifact.
- `coldStartBeats = 3` — first 3 beats accepted unconditionally to seed the median.
- `medianWindow = 5` — rolling history size.

Drop neiry's `refractoryMs`, `bufferDurationMs`, `_buffer`, `_lastPeakTs`, `_lastPpiMs`, `_currentRefractory`, `_findPeaks` — all peak-detection state that `flutter_ppg` owns.

### Method shape

`RrInterval evaluate(RrInterval rr)` — takes a kit `RrInterval` (already converted from `flutter_ppg`'s ms value at the api/processing edge, note 07/05), returns a copy with `isArtifact` set. Internal `bool _gate(int rrMs)` ports neiry lines 213–225 verbatim in spirit:

1. `if (rrMs < minRrMs) return true;` — hard lower bound, **no upper bound**.
2. `if (_rrHistory.length < coldStartBeats) return false;` — cold-start grace.
3. Compute median of sorted `_rrHistory`; `return (rrMs - median).abs() / median > consistencyThreshold;`.

Only **non-artifact** beats append to `_rrHistory` (cap at `medianWindow`, evict oldest) — matches neiry lines 116–122 so artifacts never poison the median.

`void reset()` — clear `_rrHistory` so cold-start re-seeds. Call from `CameraPpgSession.stop()` (note 07).

### Verify

`test/rr_acceptance_test.dart`, synthetic `RrInterval` sequence, no hardware:
- First 3 beats accepted even at extreme HR (e.g. 3500 ms each → `isArtifact == false`).
- `intervalMs = 250` → artifact regardless of history.
- `intervalMs = 4000` (bradycardia) after a seeded ~3000 ms median → **not** artifact (no upper bound).
- A spike (+50%) off a stable median → artifact; median unaffected (history skipped it).
- `reset()` re-arms cold-start grace.

### Guards

- Never port `_findPeaks`/refractory/buffer — duplicating flutter_ppg's DSP is the trap.
- No upper bound. No BPM/HRV. Stateful → never create a new instance per beat.
- One instance per measurement; `reset()` on stop.
