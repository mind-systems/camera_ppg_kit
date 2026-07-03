import 'dart:async';

import 'package:camera_ppg_kit/camera_ppg_kit.dart';

import '../auto_detect/log.dart';
import 'source_lifecycle.dart';

/// Example-app composition root for the kit's public barrel (spec note 16) —
/// the analogue of `neiry_kit`'s `NeiryService`, never part of the published
/// kit surface.
///
/// Plain Dart only: **no `flutter`, `flutter_riverpod`, `camera`, or
/// `flutter_ppg` imports** — it consumes `package:camera_ppg_kit/camera_ppg_kit.dart`
/// exclusively, which already hides those types.
///
/// Owns one [CameraPpgSession] across the Kit-API tab's lifetime, behind four
/// broadcast controllers opened in the constructor and kept open until
/// [dispose] — this mirrors `NeiryService`'s "streams stay open, fed on
/// start" pattern so Riverpod `StreamProvider`s can subscribe once and keep
/// listening across repeated measurements without a lazy-init-on-first-listen
/// bug or a `Bad state: Stream has already been listened to` on restart.
///
/// A fresh [CameraPpgSession] is created on every [startMeasurement] and torn
/// down by the matching [stopMeasurement] — the session itself is not reused
/// across measurements, only this service's own controllers are.
class CameraPpgService {
  CameraPpgService()
      : _rrController = StreamController<RrInterval>.broadcast(),
        _qualityController = StreamController<SignalQuality>.broadcast(),
        _stateController = StreamController<MeasurementState>.broadcast(),
        _fingerPresenceController =
            StreamController<FingerPresence>.broadcast(),
        _lifecycleController = StreamController<SourceLifecycle>.broadcast();

  final StreamController<RrInterval> _rrController;
  final StreamController<SignalQuality> _qualityController;
  final StreamController<MeasurementState> _stateController;
  final StreamController<FingerPresence> _fingerPresenceController;
  final StreamController<SourceLifecycle> _lifecycleController;

  /// Current lifecycle value — see [lifecycleStream]. The single source of
  /// truth for "what the source is doing right now" (spec note 33).
  SourceLifecycle _lifecycle = SourceLifecycle.idle;

  /// The in-flight measurement session, or `null` when idle. A new instance
  /// is created by every [startMeasurement] call and disposed by the
  /// matching [stopMeasurement].
  CameraPpgSession? _session;

  /// Set once [dispose] has run; guards against reuse after disposal.
  bool _disposed = false;

  /// Re-entry guard for [startMeasurement] (cf. neiry's `_connecting`).
  bool _measuring = false;

  /// Fan-in subscriptions bridging [_session]'s streams into this service's
  /// long-lived controllers — wired in [startMeasurement], cancelled in
  /// [stopMeasurement].
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Broadcast stream of RR intervals, fed from the current [_session] while
  /// measuring. Stays open across stop/start cycles.
  Stream<RrInterval> get rrStream => _rrController.stream;

  /// Broadcast stream of signal-quality bands. Stays open across stop/start
  /// cycles.
  Stream<SignalQuality> get qualityStream => _qualityController.stream;

  /// Broadcast stream of measurement lifecycle transitions. Stays open
  /// across stop/start cycles.
  Stream<MeasurementState> get stateStream => _stateController.stream;

  /// Broadcast stream of finger-presence classifications. Stays open across
  /// stop/start cycles.
  Stream<FingerPresence> get fingerPresenceStream =>
      _fingerPresenceController.stream;

  /// Broadcast stream of [SourceLifecycle] transitions — the single source
  /// of truth screens render Start/Stop gating and the state banner from
  /// (spec note 33), superseding per-screen `isRunning`/`canStop`
  /// derivation off the kit's [MeasurementState]. Stays open across
  /// stop/start cycles.
  Stream<SourceLifecycle> get lifecycleStream => _lifecycleController.stream;

  /// Whether a measurement session is currently in flight.
  bool get isMeasuring => _measuring && _session != null;

  /// Example-only accessor for the live preview surface (plan 25):
  /// `null` while idle, a fresh instance per measurement while running. This
  /// getter — not a `Widget? buildPreview()` on this service — is what keeps
  /// this file's no-`flutter` invariant (see class dartdoc) intact; the
  /// screen calls [CameraPpgSession.buildPreview] itself.
  CameraPpgSession? get session => _session;

  void _checkNotDisposed() {
    if (_disposed) throw StateError('CameraPpgService has been disposed');
  }

  /// Stores [next] as the current lifecycle and emits it on
  /// [lifecycleStream]. Logs a coarse milestone — the only new logging this
  /// task adds (spec note 33).
  void _setLifecycle(SourceLifecycle next) {
    final prev = _lifecycle;
    _lifecycle = next;
    if (!_lifecycleController.isClosed) {
      _lifecycleController.add(next);
    }
    ppgLog('lifecycle: ${prev.name} -> ${next.name}');
  }

  /// Starts a new measurement: creates a fresh [CameraPpgSession], pins
  /// [cameraId] if given (skipping auto-detect), wires its streams into this
  /// service's long-lived controllers, and runs [CameraPpgSession.start].
  ///
  /// [policy]/[acceptance] are `[debug]` live-tuning knobs (spec notes 09/12)
  /// forwarded straight to the session's constructor — omit both to use the
  /// kit's internal defaults.
  ///
  /// Returns `null` on success. Returns a typed [CameraPpgError] — never
  /// throws — when the session fails to lock a sensor; the failed session is
  /// torn down before returning so a subsequent call starts clean.
  ///
  /// A no-op returning `null` immediately when a measurement is already in
  /// flight — safe to call repeatedly (e.g. a double-tapped Start button).
  Future<CameraPpgError?> startMeasurement({
    String? cameraId,
    SessionPolicy? policy,
    RrAcceptance? acceptance,
  }) async {
    _checkNotDisposed();
    if (_measuring) {
      ppgLog('CameraPpgService.startMeasurement() ignored — already measuring');
      return null;
    }
    _measuring = true;
    _setLifecycle(SourceLifecycle.starting);

    final session = CameraPpgSession(policy: policy, acceptance: acceptance);
    _session = session;
    if (cameraId != null) {
      session.useCamera(cameraId);
    }

    _subs.addAll([
      session.rrStream.listen(_rrController.add, onError: _rrController.addError),
      session.qualityStream.listen(_qualityController.add, onError: _qualityController.addError),
      session.stateStream.listen(
        (state) {
          _stateController.add(state);
          _foldLifecycle(state);
        },
        onError: _stateController.addError,
      ),
      session.fingerPresenceStream.listen(
        _fingerPresenceController.add,
        onError: _fingerPresenceController.addError,
      ),
    ]);

    final error = await session.start();
    if (error != null) {
      ppgLog('CameraPpgService.startMeasurement(): start() failed — ${error.type}');
      // Tear the failed session down so state resets cleanly for a retry —
      // the caller sees `isMeasuring == false` again once this returns.
      await stopMeasurement();
    }
    return error;
  }

  /// Folds a kit [MeasurementState] emit into [_lifecycle] while a
  /// measurement is running — this is what advances `starting -> warmup` on
  /// the first kit emit and keeps lifecycle tracking `warmup`/`measuring`/
  /// `poorSignal` thereafter.
  ///
  /// Guard (spec note 33): while [_lifecycle] is already `stopping` or
  /// `idle`, every kit emit is ignored, so a late emit reaching this bridge
  /// after [stopMeasurement] has already started teardown can't bounce
  /// lifecycle back off `stopping`. A kit [MeasurementState.idle] arriving
  /// mid-run is likewise ignored — the authoritative `idle` comes only from
  /// the `stopMeasurement` teardown path, never from a stray kit emit.
  void _foldLifecycle(MeasurementState state) {
    if (_lifecycle == SourceLifecycle.stopping ||
        _lifecycle == SourceLifecycle.idle) {
      return;
    }
    switch (state) {
      case MeasurementState.warmup:
        _setLifecycle(SourceLifecycle.warmup);
      case MeasurementState.measuring:
        _setLifecycle(SourceLifecycle.measuring);
      case MeasurementState.poorSignal:
        _setLifecycle(SourceLifecycle.poorSignal);
      case MeasurementState.idle:
        break;
    }
  }

  /// Stops the current measurement (if any) and releases the camera + torch.
  ///
  /// No-op when no measurement is in flight. This service's own broadcast
  /// controllers stay open — a subsequent [startMeasurement] re-feeds them
  /// through a fresh session.
  ///
  /// A fresh [CameraPpgSession] is created on every [startMeasurement], so
  /// [CameraPpgSession.dispose] alone (not also `stop()`) is enough to
  /// release its camera + torch — calling both would just re-run the
  /// idempotent release for nothing.
  ///
  /// After teardown, this service emits a definitive terminal
  /// [MeasurementState.idle] on its own long-lived [_stateController] rather
  /// than relying on the disposed session's last emit reaching the UI — this
  /// is what returns the UI to Idle and clears stale BPM via the state
  /// cascade.
  Future<void> stopMeasurement() async {
    final session = _session;
    if (session == null) {
      _measuring = false;
      // No in-flight session to stop — this is not a real teardown, so no
      // `stopping` transition. Defensively settle a stray non-idle lifecycle
      // (there shouldn't be one), otherwise leave it as-is.
      if (_lifecycle != SourceLifecycle.idle) {
        _setLifecycle(SourceLifecycle.idle);
      }
      return;
    }
    _setLifecycle(SourceLifecycle.stopping);
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _session = null;
    _measuring = false;
    await session.dispose();
    // Push a definitive terminal idle ourselves rather than relying on the
    // session's last emit reaching the UI through the just-cancelled bridge
    // subscription above — see dartdoc.
    if (!_stateController.isClosed) {
      _stateController.add(MeasurementState.idle);
    }
    _setLifecycle(SourceLifecycle.idle);
  }

  /// Enumerates rear-facing cameras for the override UI, without a running
  /// measurement.
  ///
  /// Opens a transient, read-only [CameraPpgSession] purely to reach
  /// [CameraPpgSession.availableCameras] (which itself never opens a
  /// controller or the torch) and disposes it immediately — this never
  /// touches [_session] or this service's controllers/streams.
  Future<List<CameraPpgCameraInfo>> availableCameras() async {
    final session = CameraPpgSession();
    try {
      return await session.availableCameras();
    } finally {
      await session.dispose();
    }
  }

  /// Releases all resources. Idempotent — subsequent calls return
  /// immediately.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopMeasurement();
    await _rrController.close();
    await _qualityController.close();
    await _stateController.close();
    await _fingerPresenceController.close();
    await _lifecycleController.close();
  }
}
