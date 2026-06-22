# Code Review: flutter_ppg finger-video harness

**Plan:** `.ai-factory/plans/02-flutter-ppg-finger-video-harness.md`
**Scope reviewed:** `git diff HEAD` — 4 new code files + 2 modified, all under `example/lib/`.
**Build check:** `flutter analyze lib/` → **No issues found** (2.5s).
**Risk level:** 🟢 Low — the implementation is correct, matches the plan, and reuses the proven camera-open / ordered-teardown pattern. All findings below are minor and non-blocking.

## What was checked

- Read all six changed files in full, plus the surrounding `coverage_detector.dart`, the auto-detect screen, and the `flutter_ppg` 0.2.4 `PPGSignal` / `FlutterPPGService` source.
- Verified the three plan-review-1 safeguards were actually implemented:
  - **Broadcast keep-alive (review item 3):** `MeasurementRunner.start` creates a broadcast `StreamController` and attaches the single internal subscription to `processImageStream` (single-subscription `async*`) inside `start`, feeding the `FpsMeter` per signal and re-emitting on `signals`. ✅
  - **Timer + subscription teardown (review item 2):** `StreamInspectorScreen.dispose` cancels `_uiTimer`, cancels `_sub`, then stops the runner; the periodic tick is `mounted`-guarded. No "setState after dispose" path. ✅
  - **Empty-`rrIntervals` guard (review item 1):** `_signalPanel` renders `—` for RR and BPM when `rrIntervals.isEmpty`, and only divides when `lastRrMs > 0`. ✅
- Lifecycle: `stop()` captures-and-nulls all fields up front (idempotent / safe to call twice), tears down in the correct order, and torch-off precedes controller dispose. The screen always reaches `dispose → stop`. No double-dispose, no leaked controller in the normal flow.
- `coverage_detector.dart` refactor is behavior-identical: `isFingerPresent(raw, config: cfg)` reproduces the old `raw > min && raw < max` strict bounds, and `cfg` remains used by `FlutterPPGService(config: cfg)` (no dead variable).
- `const Stream.empty()` compiles on the installed SDK (`const factory Stream.empty()` exists in Dart 3.x).

## Findings (all non-blocking)

### 1. `FpsMeter.fps` freezes instead of decaying to 0 when frames stall (Low — correctness of the headline metric)
`example/lib/common/fps_meter.dart:20-38`. Timestamps are pruned **only inside `record`**, which is called solely on frame arrival. The `fps` getter computes over the buffered timestamps without consulting the current time. Consequence: if the frame stream stalls (finger lifted, camera stutter, or after the last frame before teardown), the UI keeps showing the last computed sustained FPS rather than dropping toward 0 — the ~3 Hz UI timer reads `sustainedFps` but no `record` call ages the stale entries out.

For a harness whose entire job is to report *achieved* sustained FPS under a static screen, a frozen non-zero reading during a stall is mildly misleading. Consider pruning against `DateTime.now()` in the getter (or returning `0.0` when the newest timestamp is older than `windowDuration`). Not a crash; the number is simply stale while frames aren't flowing.

### 2. `signals` getter doc comment is inaccurate (Nit — documentation)
`example/lib/inspector/measurement_runner.dart:36-39`. The comment states subscribers added before `start` "will receive signals once the camera opens." In fact, when `_signalsCtrl` is null the getter returns `const Stream.empty()`, which closes immediately — a pre-`start` subscriber gets `onDone` and never any data. Harmless in practice because the only caller (`_startRunner`) subscribes *after* `await _runner.start(...)`, but the comment contradicts the code. Suggest correcting it to "subscribe after `start` returns."

### 3. `start()` has no re-entrancy guard (Low — defensive)
`example/lib/inspector/measurement_runner.dart:52`. Calling `start` twice without an intervening `stop` overwrites `_controller` / `_service` / `_signalsCtrl` / `_imageStreamCtrl`, orphaning the first camera session (no teardown) — a leaked controller and torch left on. The current single caller starts exactly once, so this isn't triggered, but an early-return guard (`if (_signalsCtrl != null) return;`) or an assert would harden the class for the Phase-5 reuse it's a precursor to.

## Notes (no action)

- `fontFamily: 'monospace'` falls back to a default font on iOS — pre-existing example-app convention, cosmetic only.
- Derived BPM from a single last RR interval is noisy, but the plan explicitly scopes it to display-only (`60000 / lastRrMs`); correct per spec.
- SQI tally counters grow unbounded over a long run — irrelevant for a deliberate ~60 s hold harness.
- `dispose` does not `await runner.stop()` (sync dispose, fire-and-forget async teardown) — standard and acceptable in Flutter; the UI subscription and timer are already cancelled synchronously first, so no late callbacks fire.

## Verdict

The change is architecturally sound, compiles cleanly, honors every plan constraint (example-only, raw passthrough, throttled rebuilds, real-device tolerance), and correctly folds in all three plan-review safeguards. The three findings are quality/robustness improvements, not defects that block the milestone — finding 1 is the most worth addressing since it touches the accuracy of the harness's primary output.
