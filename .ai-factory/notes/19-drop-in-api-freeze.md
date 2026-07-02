# Integration Readiness — Drop-in API Freeze + Docs

**Date:** 2026-06-21
**Source:** ROADMAP Phase 12 ("Drop-in API freeze + docs"); ARCHITECTURE.md barrel contract; notes 05–09; `mind_mobile/docs/biometrics/active-rr-source.md` + `capability-sources.md`

## Key Findings

- This is the **freeze**, not new behaviour: lock `lib/camera_ppg_kit.dart` so `mind_mobile` can add a `camera_ppg`-tagged RR source with zero churn. The deliverable is an audited barrel + consumer docs, not code growth.
- The host contract the surface must satisfy is `ActiveRrSource` + the RR capability mixin: it consumes `RrInterval { intervalMs, timestamp, isArtifact }`, applies its own **silence window** `max(2000ms, lastIntervalMs × 2)` and **preferred-with-fallback** selection across sources, and excludes `isArtifact == true` ticks from HRV/animation. The kit must *feed* that contract, not re-implement it.
- The hard pitfall: a single leaked `PPGSignal` / `CameraImage` / `CameraController` / `MethodChannel` map in a public signature breaks the boundary and the freeze is void. The audit is the real work.
- **Boundary statement:** the `lib/Biometrics/` adapter (the `camera_ppg` `SensorSource` tag + the provider that registers this kit into `ActiveRrSource` / `BioStreamRouter`) lives in **mind_mobile**, NOT here. This note defines the surface that adapter consumes.

## Details

### What crosses the barrel (the frozen surface)

Enumerate exactly, asserting nothing else is exported from `lib/camera_ppg_kit.dart`:
- `CameraPpgSession` (note 07) — `start()`/`stop()`/`dispose()`, `rrStream`, `qualityStream`, `stateStream`; plus the selection/override API (note 08): `availableCameras()`, `useCamera(id)`.
- `RrInterval` (note 05) — shape-identical to neiry's `RRInterval` so the host's RR mixin binds both sources with one type.
- `SignalQuality` + `fromSnr` (note 05).
- `MeasurementState`, `FingerPresence`, `CameraPpgError` (note 06) — typed values, never thrown.
- `CameraPpgCameraInfo` (note 08).

### Debug-tagged extras — present in the public API, NOT part of the consumer contract

For the freeze to be **honest** it must name what the playground (note 14) uses but the host does not. These two are the *only* `[debug]` surfaces; the audit confirms there are no others:
- **Input:** an optional `RrAcceptanceConfig? acceptance` on the `CameraPpgSession` ctor (default `null` → internal gate defaults, note 12). The host always omits it; it exists for spike tuning and tests.
- **Output:** `Stream<List<double>> debugSignalStream` (note 07) — the red-channel waveform for the example's signal-existence diagnostic. `List<double>` only.
Neither is part of the drop-in contract `mind_mobile` codes against; both must be explicitly labelled debug in the docs so no consumer mistakes them for the supported surface.

### Contract-fit assertions (current state → confirm at freeze)

- **Source tagging:** the kit does NOT emit a `SensorSource`; that tag is applied by the mind_mobile adapter. Confirm `RrInterval` carries no source field — keep it neutral so the adapter stamps `camera_ppg` at the boundary.
- **RR-only source — no HR stream (unlike neiry).** `flutter_ppg`'s `PPGSignal` (verified, 0.2.4) exposes only `rrIntervals`/`peakIndices`/`snr`/`quality`/intensities — **no independent heart-rate estimate**; any BPM in the package (and downstream) is literally `60000 / mean(rrIntervals)`, a pure derivative of RR. So camera_ppg has **one** datum (RR); HR is not separate data. This is the structural difference from neiry, whose SDK `CardioClassifier` produces HR by its **own** algorithm distinct from the peak-detected RR — two producers, so `NeiryBciProvider` implements both `IHeartRateSource` and `IRrIntervalSource`. The camera_ppg adapter (mind_mobile) implements **only `IRrIntervalSource`**; if the app needs an HR number from this source it derives it downstream from RR. The kit therefore exposes no HR/BPM stream and no `IHeartRateSource`-shaped surface — RR + quality only.
- **Artifact exclusion:** `RrInterval.isArtifact` is the only artifact channel; `ActiveRrSource`'s single `if (rr.isArtifact)` and `SmoothedRrSource`'s filter depend on it. The kit must set it (Phase 8 gate), never silently drop intervals.
- **Silence-window semantics:** the kit's `rrStream` simply stops emitting on no-finger/poor-signal (note 09 transitions to `poorSignal`); it must NOT emit zero/placeholder intervals, so the host's `max(2000ms, lastIntervalMs × 2)` timer fires correctly and falls back to a worn sensor / `ClockTickService`.
- **`SignalQuality`/`qualityStream` — exported but not RR-contract-consumed (conscious keep).** Confirmed against `active-rr-source.md`: the `ActiveRrSource` contract reads only `RrInterval {intervalMs, timestamp, isArtifact}` — nothing in the host's biometrics layer reads `SignalQuality`/SNR. SQI is retained on the frozen surface deliberately: it is the *internal* driver of `MeasurementState.poorSignal` (note 09) and is plausibly useful to the host's measurement-UI guidance ("press your finger") even though the RR source ignores it. Keep — but as a known, cheap convenience, not a contract dependency. The numeric `snr` rides along on the `SignalQuality` value (note 05) and is `[debug]`-grade for the example; the host need not read it.
- **Preferred-with-fallback:** kit-side requires nothing; just clean start/stop and an honest silent stream when signal is lost.

### Docs update

Update `README.md` Status section (currently "early stage / being built out") to a stable-surface statement, and add a short "Consuming as a heart-rate source" section: import the barrel only, the three streams + state machine, and the explicit note that the adapter/tag belongs in the host. Do not add a directory tree or an API method table (per doc rules — describe behaviour).

### Verify

- `grep -rE 'flutter_ppg|CameraImage|CameraController|MethodChannel' lib/camera_ppg_kit.dart` → no hits.
- Every `export` in the barrel resolves to a `src/models/` or `src/api/` file; `src/channel`, `src/processing`, `src/util` are NOT exported.
- A throwaway consumer importing only the barrel can subscribe to all three streams and read every public type without touching `src/`.

### Guards

- No new public types at freeze — additions are a deliberate post-freeze act.
- Do not add BPM/HRV, a `SensorSource` field, or a registration helper to the kit — those are host concerns.
- Keep `poorSignal`/no-finger as silent-stream + typed state, never an exception — the host's silence window relies on absence, not errors.
