# CameraPpgService Device-Layer Singleton

**Date:** 2026-06-21
**Source:** ROADMAP Phase 10 ("CameraPpgService device-layer singleton — plain Dart service owning the camera + `flutter_ppg` lifecycle behind broadcast streams, exposed via a Riverpod provider — mirrors neiry's `NeiryService`"); `neiry_kit/example/lib/services/neiry_service.dart` + `providers/neiry_service_provider.dart`; note 07 (CameraPpgSession).

## Key Findings

- This is the **example app's composition root** for the kit — the analogue of neiry's `NeiryService`, not part of the published kit surface. It lives in `example/lib/services/camera_ppg_service.dart` and owns one `CameraPpgSession` (the public barrel type from note 07) across the screen's lifetime, so a tab switch / widget rebuild never re-inits the camera or drops a stream.
- The crux ported from neiry: **broadcast `StreamController`s opened in the constructor and kept open until `dispose()`**, fed by fan-in subscriptions wired on `startMeasurement()` and cancelled on `stopMeasurement()`. Subscribers (Riverpod `StreamProvider`s) attach before measurement starts and survive a stop/start cycle — no lazy-init-on-first-listen bug.
- Plain Dart only: **no `flutter`, `flutter_riverpod`, or `camera`/`flutter_ppg` imports** in the service. It consumes the kit barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`) which already hides `CameraImage`/`PPGSignal`. Riverpod lives only in the thin provider file.

## Details

### `example/lib/services/camera_ppg_service.dart` (new — plain Dart class)

Mirror `NeiryService`'s skeleton, scoped to one session:
- Owns `CameraPpgSession? _session`, a `bool _disposed`, and a `_measuring` re-entry guard (cf. neiry's `_connecting`).
- Constructor opens three broadcast controllers: `StreamController<RrInterval>.broadcast()`, `StreamController<SignalQuality>.broadcast()`, `StreamController<MeasurementState>.broadcast()`. Exposes `rrStream` / `qualityStream` / `stateStream` getters off `.stream`.
- `Future<void> startMeasurement({CameraId? camera})` — `_checkNotDisposed()`; guard `if (_measuring) throw StateError(...)`; create the `CameraPpgSession` (passing the optional camera-override id from note 08, otherwise signal-based auto-detect picks the covered sensor — note 01); wire fan-in subscriptions from the session's three streams into the controllers (`.listen(_rrController.add, onError: _rrController.addError)` for each), holding them in a `List<StreamSubscription<dynamic>> _subs`; then `await _session!.start()`.
- `Future<void> stopMeasurement()` — no-op when `_session == null`; cancel + clear `_subs`, then `await _session!.stop()`/`dispose()`, null out `_session`. Controllers **stay open** so the next `startMeasurement()` re-feeds them (the neiry "multiplexer controllers stay open" invariant).
- `Future<void> dispose()` — idempotent (`if (_disposed) return; _disposed = true;`); `await stopMeasurement()`; close all three controllers.
- State getters: `bool get isMeasuring => _measuring && _session != null;` (and pass through `_session?` state if the session exposes one).

Camera selection lives in the session: the service forwards only an **optional override id** (note 08) and lets the session's signal-based auto-detect pick the covered sensor. The service neither enumerates nor selects.

### `example/lib/providers/camera_ppg_service_provider.dart` (new)

Exact shape of `neiry_service_provider.dart`:
```dart
final cameraPpgServiceProvider = Provider<CameraPpgService>((ref) {
  final s = CameraPpgService();
  ref.onDispose(s.dispose);
  return s;
});
```
Plus per-stream `StreamProvider`s mirroring `rr_provider.dart` (e.g. `rrProvider`, `qualityProvider`, `stateProvider`) that `ref.watch(cameraPpgServiceProvider).rrStream`. The Phase 9 playground screen (note 14) consumes these, never the service directly.

### Verify

- Start measurement, switch tabs / rebuild the screen, return — RR events still flow on the same `rrProvider` subscription (controllers were not recreated).
- `stopMeasurement()` then `startMeasurement()` re-delivers events to the same subscribers with no `Bad state: Stream has already been listened to`.
- Tear down the provider scope → `ref.onDispose` fires `dispose()`, releasing camera + torch with no late events.

### Guards

- No `flutter_ppg` / `camera` / `MethodChannel` type appears in the service's public signatures — only kit barrel models (`RrInterval`, `SignalQuality`, `MeasurementState`).
- Service is plain Dart: Riverpod and `ref.onDispose` belong to the provider file only.
- Do not duplicate session policy (note 09) here — warm-up / acceptance / duration live inside `CameraPpgSession`; the service is lifecycle + fan-in only.
- Keep internal logs behind the single kit log helper (`src/util`, cf. neiry's `nlog`), not raw `print`.
