import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera/camera.dart' as cam show availableCameras;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ppg/flutter_ppg.dart' hide SignalQuality;

import '../models/camera_ppg_camera_info.dart';
import '../models/camera_ppg_error.dart';
import '../models/finger_presence.dart';
import '../models/measurement_state.dart';
import '../models/rr_interval.dart';
import '../models/signal_quality.dart';
import '../processing/frame_isolate.dart';
import '../processing/frame_message.dart';
import '../processing/rr_acceptance.dart';
import '../processing/rr_dehalving.dart';
import '../processing/session_policy.dart';
import '../util/nlog.dart';
import 'rr_diff.dart';

/// Fraction of dwell-window frames that must read as [FingerPresence.present]
/// for a probed sensor to be considered covered.
const double _coverageThreshold = 0.6;

/// Frames received during this window (after opening a probed camera) are
/// discarded to let torch/exposure settle before evaluating coverage.
const Duration _probeWarmUp = Duration(milliseconds: 400);

/// Window (after [_probeWarmUp]) over which covered-frame fraction is
/// evaluated for a single probed sensor.
const Duration _probeDwell = Duration(milliseconds: 700);

/// Owns a single contact-PPG measurement session over the rear camera +
/// torch, and fans out kit-model streams derived from it.
///
/// This is the kit's public measurement surface — the analogue of
/// `neiry_kit`'s `Device`. It owns a `package:camera` `CameraController` and
/// a `package:flutter_ppg` `FlutterPPGService` internally; neither type (nor
/// `CameraImage`/`PPGSignal`) ever crosses a public signature. [start] runs
/// the signal-based auto-detect round-trip over the rear sensors and locks
/// the first one a finger is detected on; [stop]/[dispose] release the
/// camera and torch through a single ordered teardown.
///
/// The broadcast streams below are opened once, in the constructor, and
/// stay open across repeated `start()`/`stop()` cycles — only [dispose]
/// closes them. This mirrors `neiry_kit`'s `NeiryService` "streams stay
/// open, fed on start" pattern, so consumers can subscribe once and keep
/// listening across measurements.
class CameraPpgSession {
  CameraPpgSession({
    SessionPolicy? policy,
    RrAcceptance? acceptance,
    RrDehalving? dehalving,
  })  : _rrController = StreamController<RrInterval>.broadcast(),
        _qualityController = StreamController<SignalQuality>.broadcast(),
        _stateController = StreamController<MeasurementState>.broadcast(),
        _debugSignalController = StreamController<List<double>>.broadcast(),
        _fingerPresenceController =
            StreamController<FingerPresence>.broadcast(),
        _policy = policy ?? SessionPolicy(),
        _acceptance = acceptance ?? RrAcceptance(),
        _dehalving = dehalving ?? RrDehalving();

  final StreamController<RrInterval> _rrController;
  final StreamController<SignalQuality> _qualityController;
  final StreamController<MeasurementState> _stateController;
  final StreamController<List<double>> _debugSignalController;
  final StreamController<FingerPresence> _fingerPresenceController;

  /// Warm-up/duration/acceptance policy (spec note 09) that drives [_state]
  /// once a sensor is locked. Constructor-injectable so the example's
  /// settings playground can pass a tuned instance; defaults to a fresh
  /// [SessionPolicy] otherwise.
  final SessionPolicy _policy;

  /// Per-beat physiological acceptance gate (spec note 12) that flags
  /// [RrInterval.isArtifact] before beats reach consumers. Constructor-
  /// injectable, mirroring [_policy], so the example's live-tuning
  /// playground and tests can pass a tuned instance; defaults to a fresh
  /// [RrAcceptance] otherwise.
  final RrAcceptance _acceptance;

  /// Adaptive RR-domain de-halving stage (spec note 30) that merges
  /// harmonic-paired short beats before they reach [_acceptance] — killing
  /// the peak-halving inversion the calibration runs exposed. Constructor-
  /// injectable, mirroring [_policy]/[_acceptance]; defaults to a fresh
  /// [RrDehalving] otherwise.
  final RrDehalving _dehalving;

  /// Monotonic elapsed-time source for [_policy] — reset and started when a
  /// sensor locks, stopped on [_release]. The policy itself stays pure and
  /// never reads a clock; only the session does, passing [Stopwatch.elapsed]
  /// into [SessionPolicy.onSignal] on every tick.
  final Stopwatch _stopwatch = Stopwatch();

  /// Current lifecycle state, driven tick-by-tick by [_policy] once a sensor
  /// locks: [MeasurementState.idle] when not running, then
  /// `warmup → measuring ⇄ poorSignal → done` per [SessionPolicy].
  MeasurementState _state = MeasurementState.idle;

  /// Double-start / re-entrancy guard for [start] (review F3).
  bool _running = false;

  /// Set once [dispose] has run; guards against reuse after disposal.
  bool _disposed = false;

  /// Manual-override pin set via [useCamera]. `null` means auto-detect (the
  /// default): [start] runs the signal-based coverage round-trip. Non-null
  /// means the next [start] resolves this id against the enumerated rear
  /// cameras and locks it directly, skipping the round-trip entirely.
  String? _pinnedCameraId;

  /// Bumped by every [_release] call. [start] captures the value in force
  /// when it begins and re-checks it after each `await` during camera
  /// setup; a mismatch means a concurrent [stop]/[dispose] ran while
  /// [start] was suspended, so it abandons the in-flight attempt instead of
  /// resuming and stranding a second camera/torch behind the caller's back
  /// (review Finding 1).
  int _generation = 0;

  // Internal camera/frame-isolate handles. The measurement frame path runs
  // through a long-lived background isolate (spec note 13 / plan 09) rather
  // than a UI-isolate `FlutterPPGService` — see [FrameIsolate].
  CameraController? _controller;
  FrameIsolate? _frameIsolate;
  StreamSubscription<SignalMessage>? _sub;

  /// Last-seen `PPGSignal.rrIntervals` window, used to diff out only the
  /// newly-produced interval(s) on each signal (see [rr_diff.dart]).
  List<double> _lastRrIntervals = const [];

  /// Broadcast stream of RR intervals derived from the PPG signal.
  Stream<RrInterval> get rrStream => _rrController.stream;

  /// Broadcast stream of coarse signal-quality bands derived from the
  /// PPG signal's SNR.
  Stream<SignalQuality> get qualityStream => _qualityController.stream;

  /// Broadcast stream of measurement lifecycle transitions.
  Stream<MeasurementState> get stateStream => _stateController.stream;

  /// `[debug]` — raw/filtered red-channel samples tapped off the same
  /// `PPGSignal` used to derive [rrStream]/[qualityStream].
  ///
  /// This is a debug-only extra for the example inspector and tests — it is
  /// **absent from the consumer contract** (see note 19's freeze). It stays
  /// `List<double>` only; no `flutter_ppg`/`camera` type ever crosses it.
  Stream<List<double>> get debugSignalStream => _debugSignalController.stream;

  /// Broadcast stream of finger-presence classifications, updated on every
  /// signal tick in every [MeasurementState].
  ///
  /// Lets the host distinguish "press your finger" ([FingerPresence.absent])
  /// from "finger not covering the lens" ([FingerPresence.overBright]) from
  /// "hold still / low SNR" ([qualityStream] alone can't express that
  /// distinction) to render acceptance-gate guidance.
  Stream<FingerPresence> get fingerPresenceStream =>
      _fingerPresenceController.stream;

  /// Live camera texture for the session's own locked controller, or `null`
  /// when there is nothing to show.
  ///
  /// Reads the existing controller only — it never opens a second one (the
  /// rear camera + torch cannot be opened twice, spec note 01) — so this
  /// returns non-null only between lock and teardown: `null` while idle,
  /// during the pre-lock auto-detect probe, and after [stop]/[dispose] null
  /// out [_controller]. The returned [Widget] wraps [CameraPreview]
  /// internally but the signature itself is a plain `package:flutter` type,
  /// so no `camera`/`CameraController` type crosses this method.
  Widget? buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraPreview(controller);
  }

  /// Pins the next [start] to the rear camera identified by [id] (one of the
  /// ids returned by [availableCameras]), skipping the signal-based
  /// auto-detect round-trip entirely.
  ///
  /// Must be called before [start] — it only records the pin; [start] reads
  /// it. There is no mid-stream hot-swap. Calling this again replaces the
  /// previous pin. There is no un-pin API; auto-detect is the default and
  /// this milestone doesn't need one.
  ///
  /// Throws [StateError] if called while a measurement is already in
  /// flight. This is keyed on [_running] rather than `_state ==
  /// MeasurementState.measuring` deliberately: [_running] is set at the very
  /// top of [start] for the whole auto-detect round-trip, before state
  /// reaches [MeasurementState.measuring], so this also correctly rejects
  /// [useCamera] during that pre-`measuring` setup window.
  void useCamera(String id) {
    if (_running) {
      throw StateError('useCamera() cannot be called while a measurement is running');
    }
    _pinnedCameraId = id;
  }

  /// Runs the signal-based auto-detect round-trip over the rear sensors,
  /// locks the first one a finger is detected on, and starts streaming RR
  /// intervals / quality / debug signal from it.
  ///
  /// Returns `null` on success (state moves to [MeasurementState.warmup],
  /// then advances through [SessionPolicy] as signal ticks arrive).
  /// Returns a typed [CameraPpgError] — never throws — when no sensor reads
  /// as covered, camera/torch setup fails, or permission is denied; the
  /// session returns to [MeasurementState.idle] in every failure case.
  ///
  /// Calling [start] again while already running is a no-op that returns
  /// `null` immediately (review F3) — safe to call repeatedly, e.g. from a
  /// double-tapped "Start" button.
  ///
  /// If [stop]/[dispose] runs concurrently while this call is suspended on
  /// an `await` (e.g. `session.start(); await session.stop();` without
  /// awaiting `start`), the in-flight attempt notices via [_generation] and
  /// abandons itself — tearing down whatever it had already opened — rather
  /// than resuming after the caller believes the session is stopped and
  /// silently stranding a live camera + torch (review Finding 1).
  Future<CameraPpgError?> start() async {
    if (_disposed) {
      nlog('start() ignored — session disposed');
      return CameraPpgError.cameraUnavailable(message: 'session disposed');
    }
    if (_running) {
      nlog('start() ignored — already running');
      return null;
    }
    _running = true;
    final generation = _generation;
    bool stale() => _generation != generation;

    var lockedAndStreaming = false;
    try {
      final cameras = await _enumerateRearCameras();
      if (stale()) {
        nlog('start(): abandoned — stop()/dispose() ran during enumeration');
        return null;
      }
      if (cameras.isEmpty) {
        nlog('start(): no rear camera available');
        return CameraPpgError.cameraUnavailable(
          message: 'no rear camera available',
        );
      }

      final CameraDescription description;
      final pinnedCameraId = _pinnedCameraId;
      if (pinnedCameraId != null) {
        // Manual override (see [useCamera]): skip the coverage round-trip
        // entirely and lock the pinned sensor directly. No `await` happens
        // between the `stale()` check above and here, so the generation
        // discipline stays intact without an extra check.
        final pinned = _resolvePinnedCamera(cameras, pinnedCameraId);
        if (pinned == null) {
          nlog('start(): pinned camera not found — $pinnedCameraId');
          return CameraPpgError.cameraUnavailable(
            message: 'pinned camera not found: $pinnedCameraId',
          );
        }
        description = pinned;
        nlog('start(): using pinned camera ${description.name}, skipping auto-detect round-trip');
      } else {
        final lockResult = await _lockCoveredCamera(cameras);
        if (stale()) {
          nlog('start(): abandoned — stop()/dispose() ran during the coverage probe');
          return null;
        }
        if (lockResult.error != null) {
          nlog('start(): no covered sensor — ${lockResult.error!.type}');
          return lockResult.error;
        }
        description = lockResult.camera!;
      }

      // Built up locally and only promoted to the instance fields once
      // fully wired (see below). If [stale] flips true partway through,
      // this local session is torn down directly — the shared fields were
      // never touched, so `_release()` (already run by the concurrent
      // stop()/dispose()) has nothing left to do.
      CameraController? controller;
      FrameIsolate? frameIsolate;
      StreamSubscription<SignalMessage>? sub;

      try {
        controller = CameraController(
          description,
          ResolutionPreset.low,
          enableAudio: false,
          // iOS expects bgra8888; Android expects yuv420.
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420,
        );
        await controller.initialize();
        if (stale()) {
          nlog('start(): abandoned — stop()/dispose() ran during controller.initialize()');
          return null;
        }
        await controller.setFlashMode(FlashMode.torch);

        // Best-effort exposure/focus lock — auto-exposure/focus chase and
        // flatten the PPG signal; locking improves stability where
        // supported. Focus lock times out on some devices — catch and
        // continue.
        try {
          await controller.setExposureMode(ExposureMode.locked);
        } catch (e) {
          nlog('setExposureMode(locked) not supported on this device: $e');
        }
        try {
          await controller.setFocusMode(FocusMode.locked);
        } catch (e) {
          nlog('setFocusMode(locked) not supported on this device: $e');
        }
        if (stale()) {
          nlog('start(): abandoned — stop()/dispose() ran during torch/lock setup');
          return null;
        }

        // Route frames through a long-lived background isolate (spec note 13
        // / plan 09) instead of a UI-isolate FlutterPPGService — a heavy
        // co-tenant screen can't starve the frame stream if the DSP work
        // never runs on the UI isolate to begin with.
        frameIsolate = await FrameIsolate.spawn();
        if (stale()) {
          nlog('start(): abandoned — stop()/dispose() ran while spawning the frame isolate');
          return null;
        }

        // `fi` is a non-nullable capture for the closure below — safe
        // because it is assigned once, immediately above, and never
        // reassigned to null in this scope; `FrameIsolate.sink()` itself is
        // a no-op after `dispose()`, so a late frame callback after
        // teardown cannot crash (the isolate analogue of the `?.`-guarded
        // `imageStreamCtrl` bridge used elsewhere in this file).
        final fi = frameIsolate;
        controller.startImageStream((img) {
          // frameMessageFromCameraImage reads planes[2] for yuv420; a
          // nonconformant frame layout (not observed on tested hardware,
          // but not guaranteed by the platform) would otherwise throw
          // uncaught inside this raw camera-plugin callback. Previously
          // flutter_ppg's own `try { extractRedChannel } catch { continue }`
          // absorbed malformed frames — restore that same drop-and-continue
          // posture here now that plane extraction runs before the isolate
          // boundary (review round-2 Finding 2).
          try {
            fi.sink(frameMessageFromCameraImage(img));
          } catch (e) {
            nlog('dropping malformed camera frame: $e');
          }
        });

        sub = frameIsolate.signals.listen(
          _onSignal,
          onError: (Object e, StackTrace st) {
            nlog('frame isolate signal stream error', error: e, stackTrace: st);
          },
        );

        if (stale()) {
          nlog('start(): abandoned — stop()/dispose() ran while wiring the signal stream');
          return null;
        }

        _controller = controller;
        _frameIsolate = frameIsolate;
        _sub = sub;
        _lastRrIntervals = const [];
        _policy.reset();
        _stopwatch
          ..reset()
          ..start();
        _setState(MeasurementState.warmup);
        lockedAndStreaming = true;
        nlog('start(): locked ${description.name}, streaming');
        return null;
      } finally {
        // Never promoted to the instance fields (either an early return
        // above, or an exception below caught by the outer clauses) — tear
        // this local session down directly so it can't leak a camera/torch
        // behind fields the outer `_release()` doesn't know about.
        if (!lockedAndStreaming) {
          await _tearDownHandles(
            controller: controller,
            frameIsolate: frameIsolate,
            signalSub: sub,
          );
        }
      }
    } on CameraException catch (e) {
      nlog('CameraException in start(): ${e.code} ${e.description}');
      return CameraPpgError.fromCameraErrorCode(e.code, description: e.description);
    } catch (e, st) {
      nlog('Unexpected error in start()', error: e, stackTrace: st);
      return CameraPpgError.cameraUnavailable(message: e.toString());
    } finally {
      // Only run the session-global reset when this call still owns the
      // session. If `stale()` is true, a concurrent stop()/dispose()
      // already ran `_release()` (and possibly a newer `start()` has since
      // taken ownership) — the local handles are already torn down by the
      // inner `finally` above, so running `_release()` again here would
      // clobber state a newer call owns (review round-2 Finding 1).
      if (!lockedAndStreaming && !stale()) {
        await _release();
      }
    }
  }

  /// Stops the current measurement and releases the camera + torch.
  ///
  /// The broadcast streams stay open — a subsequent [start] reuses them,
  /// matching the "streams stay open, fed on start" pattern.
  Future<void> stop() async {
    await _release();
  }

  /// Releases the camera + torch (if running) and permanently closes the
  /// broadcast streams. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _release();
    await _rrController.close();
    await _qualityController.close();
    await _stateController.close();
    await _debugSignalController.close();
    await _fingerPresenceController.close();
  }

  /// Single ordered, idempotent teardown used by [stop], [dispose], and
  /// every failure path in [start].
  ///
  /// Captures and nulls all handles atomically first (so a re-entrant call
  /// is a no-op) and clears [_running] before releasing anything, so a
  /// stranded [_running] can never make a subsequent [start] a permanent
  /// no-op. Order (spike-proven invariant, see coverage_detector.dart /
  /// measurement_runner.dart in example/):
  /// 1. stop the camera image stream
  /// 2. close the `StreamController<CameraImage>` bridge BEFORE cancelling
  ///    the `PPGSignal` subscription — `processImageStream` is an `async*`
  ///    generator parked on `await for`; cancelling first deadlocks it.
  /// 3. cancel the `PPGSignal` subscription
  /// 4. dispose the PPG service
  /// 5. torch off
  /// 6. dispose the camera controller
  Future<void> _release() async {
    final controller = _controller;
    final frameIsolate = _frameIsolate;
    final sub = _sub;

    _controller = null;
    _frameIsolate = null;
    _sub = null;
    _running = false;
    // Invalidates any in-flight `start()` still suspended on an `await` —
    // see [_generation]'s doc (review Finding 1).
    _generation++;
    _stopwatch.stop();
    _acceptance.reset();
    _dehalving.reset();

    await _tearDownHandles(
      controller: controller,
      frameIsolate: frameIsolate,
      signalSub: sub,
    );

    _setState(MeasurementState.idle);
    nlog('session released');
  }

  /// Shared ordered teardown for a set of camera/frame-processing handles —
  /// every field is optional and independently tolerated as absent. Two
  /// independent handle shapes share this helper:
  /// - **Probe shape** (`imageStreamCtrl`/`service`/`sub`): used by
  ///   [_probeCameraCoverage]'s per-probe local handles, which still bridge
  ///   `startImageStream` straight into a UI-isolate `FlutterPPGService`
  ///   (short-lived, not FPS-sensitive — out of the isolate-offload scope
  ///   per spec note 13).
  /// - **Session shape** (`frameIsolate`/`signalSub`): used by [_release]
  ///   (session-owned handles) and [start]'s mid-setup abandon path (local
  ///   handles not yet promoted to session fields) — the sustained
  ///   measurement path, routed through [FrameIsolate].
  ///
  /// Order (spike-proven invariant, see coverage_detector.dart /
  /// measurement_runner.dart in example/, mirrored *inside* the isolate for
  /// the session shape by [FrameIsolate.dispose]):
  /// 1. stop the camera image stream
  /// 2. close/stop feeding the frame path — probe shape: close the
  ///    `StreamController<CameraImage>` bridge BEFORE cancelling the
  ///    `PPGSignal` subscription (`processImageStream` is an `async*`
  ///    generator parked on `await for`; cancelling first deadlocks it);
  ///    session shape: cancel the `SignalMessage` subscription, then let
  ///    [FrameIsolate.dispose] run the same close-before-cancel ordering
  ///    inside the isolate before it is killed.
  /// 3. dispose the PPG service / frame isolate
  /// 4. torch off
  /// 5. dispose the camera controller
  Future<void> _tearDownHandles({
    CameraController? controller,
    StreamController<CameraImage>? imageStreamCtrl,
    FlutterPPGService? service,
    StreamSubscription<PPGSignal>? sub,
    FrameIsolate? frameIsolate,
    StreamSubscription<SignalMessage>? signalSub,
  }) async {
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (e) {
        nlog('stopImageStream failed', error: e);
      }
    }

    // Probe shape.
    await imageStreamCtrl?.close();
    await sub?.cancel();
    service?.dispose();

    // Session shape — cancel the main-isolate subscription to
    // `frameIsolate.signals` first, then let the isolate run its own
    // close-before-cancel teardown before it is killed.
    await signalSub?.cancel();
    await frameIsolate?.dispose();

    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (e) {
        nlog('setFlashMode(off) failed', error: e);
      }
    }

    await controller?.dispose();
  }

  /// Converts a [SignalMessage] (the sendable subset of `PPGSignal` produced
  /// inside [FrameIsolate]) to kit models, advances [_policy], and fans the
  /// result out on the broadcast streams. No `flutter_ppg`/isolate type
  /// leaves this method.
  void _onSignal(SignalMessage signal) {
    if (signal.isError) {
      // Isolate-side failures cross as data (spec note 13 Guards) — log and
      // drop the tick rather than throwing; the next signal recovers state
      // normally.
      nlog('frame isolate signal error: ${signal.error}');
      return;
    }

    // RR bookkeeping — diff + `_lastRrIntervals` update — runs
    // unconditionally, every tick, regardless of trust state (see the RR
    // gating note below). PPGSignal.rrIntervals (mirrored 1:1 into
    // SignalMessage.rrIntervals) is recomputed from scratch every frame from
    // a sliding window, not an append-only log — this diffs out only the
    // newly-produced interval(s). Artifact detection itself happens
    // per-beat in the RR-gating block below via [_acceptance] (note 12).
    final newIntervals = diffNewIntervals(_lastRrIntervals, signal.rrIntervals);
    _lastRrIntervals = signal.rrIntervals;

    // The kit's own SignalQuality (from SNR), never flutter_ppg's
    // PPGSignal.quality — SignalMessage never carries that field at all.
    final quality = SignalQuality.fromSnr(signal.snr);
    final presence = FingerPresence.fromRawIntensity(signal.rawIntensity);

    // Advance the warm-up/duration/acceptance policy (spec note 09) with
    // this tick's elapsed time off the session's own [_stopwatch] — the
    // policy itself stays pure and never reads a clock.
    final next = _policy.onSignal(
      elapsed: _stopwatch.elapsed,
      quality: quality,
      presence: presence,
    );

    // RR gating — gate only the emit, not the bookkeeping above. If the
    // whole block (diff + `_lastRrIntervals` update) were guarded by
    // `rrTrusted` instead, `_lastRrIntervals` would stay stale through
    // warm-up/poorSignal, and the first trusted tick afterwards would diff
    // against a stale window and dump the entire withheld window as
    // "trusted" — exactly the beats the spec says to withhold. Keeping the
    // bookkeeping unconditional means those beats are quietly consumed and
    // discarded, not deferred.
    if (_policy.rrTrusted) {
      // Frame-processing timestamp, reconstructed from the sendable
      // SignalMessage.timestampMicros (mirrors PPGSignal.timestamp) once per
      // tick rather than per interval below.
      final timestamp = DateTime.fromMicrosecondsSinceEpoch(signal.timestampMicros);
      for (final rr in newIntervals) {
        // Timestamp caveat: assigned to every interval in this batch — a
        // fair approximation for this passthrough, but it diverges from
        // RrInterval.timestamp's "later peak" contract. PPGSignal.peakIndices
        // would give precise per-peak timing if a later phase wants it, but
        // SignalMessage deliberately doesn't carry it (not part of the five
        // fields _onSignal consumes).
        final candidate = RrInterval(
          intervalMs: rr.round(),
          timestamp: timestamp,
          isArtifact: false,
        );

        // De-halving (spec note 30) runs before the acceptance gate, and
        // every trusted candidate is fed to it unconditionally — its
        // pending/pair state depends on seeing every beat in order, so a
        // dropped feed would corrupt the next merge decision. It buffers
        // internally, so a given feed may resolve no output (`null`, held
        // pending a partner), exactly one, or occasionally an extra
        // previously-buffered interval — do not assume 1:1 parity with
        // `newIntervals`.
        final dehalved = _dehalving.evaluate(candidate);
        if (dehalved == null) continue;

        // Only the terminal emit needs the closed-controller guard — a
        // teardown-race tick still feeds the de-halving stage above (so its
        // state stays correct for whatever measurement follows) but must
        // not add to a closed controller.
        if (_rrController.isClosed) continue;

        // Every de-halved interval is fed through [_acceptance], artifact or
        // not — its own history-append logic already skips artifacts, so
        // there is no need to pre-filter here.
        _rrController.add(_acceptance.evaluate(dehalved));
      }
    }

    // Quality/finger-presence/debug streams flow in every state — the host
    // renders quality and guidance continuously, not just while measuring.
    if (!_qualityController.isClosed) {
      _qualityController.add(quality);
    }

    if (!_fingerPresenceController.isClosed) {
      _fingerPresenceController.add(presence);
    }

    if (!_debugSignalController.isClosed) {
      _debugSignalController.add([signal.rawIntensity, signal.filteredIntensity]);
    }

    _setState(next);
  }

  void _setState(MeasurementState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Returns every rear-facing camera in [availableCameras] enumeration
  /// order (default/main-wide first on iOS; single logical back on
  /// Android). [CameraDescription.lensType] is frequently `unknown`, so
  /// lenses are probed in enumeration order rather than ranked by type.
  Future<List<CameraDescription>> _enumerateRearCameras() async {
    final all = await cam.availableCameras();
    return all.where((c) => c.lensDirection == CameraLensDirection.back).toList();
  }

  /// Descriptive list of every selectable rear-facing camera, for
  /// diagnostics and manual override via [useCamera].
  ///
  /// Read-only — this never opens a controller or touches the torch, unlike
  /// the coverage round-trip in [_lockCoveredCamera]. Android yields one
  /// logical back entry; iOS yields one per rear lens. The metadata on each
  /// [CameraPpgCameraInfo] is descriptive only (see that type's doc) and
  /// must never be used to select a sensor — normal operation is the
  /// signal-based auto-detect round-trip in [start].
  ///
  /// Never throws: the underlying `camera` plugin's `availableCameras()` can
  /// throw a `CameraException` on a platform-side enumeration failure, but
  /// this method keeps the kit's "no exceptions across the boundary"
  /// discipline (matching every other public entry point) by catching it
  /// and returning an empty list instead — "enumeration failed" and "no
  /// rear cameras" both surface the same way to a diagnostics/override
  /// list, which has no error-value channel of its own.
  Future<List<CameraPpgCameraInfo>> availableCameras() async {
    List<CameraDescription> cameras;
    try {
      cameras = await _enumerateRearCameras();
    } on CameraException catch (e) {
      nlog('availableCameras(): enumeration failed — ${e.code} ${e.description}');
      return const [];
    }
    return cameras
        .map((d) => CameraPpgCameraInfo(
              id: d.name,
              lensType: d.lensType.name,
              flashAvailable: true,
            ))
        .toList();
  }

  /// Pure lookup resolving a [useCamera]-pinned id against the enumerated
  /// rear [cameras] by [CameraDescription.name]. Returns `null` when no
  /// entry matches — [start] maps that to a typed
  /// [CameraPpgError.cameraUnavailable] rather than silently falling back
  /// to auto-detect.
  CameraDescription? _resolvePinnedCamera(
    List<CameraDescription> cameras,
    String id,
  ) {
    for (final c in cameras) {
      if (c.name == id) return c;
    }
    return null;
  }

  /// Runs the sequential coverage round-trip over [cameras] and returns the
  /// first sensor whose finger-presence test passes during the dwell
  /// window, or a typed failure.
  ///
  /// Cameras cannot be opened concurrently: each probe tears its own
  /// controller down (via [_probeCameraCoverage]'s `finally`) before the
  /// next one opens, so at most one `CameraController` is ever open here.
  /// A [CameraException] during a probe stops the round-trip immediately
  /// and maps to a typed [CameraPpgError]; if no sensor is covered, the
  /// round-trip returns [CameraPpgError.noFinger].
  Future<_LockResult> _lockCoveredCamera(List<CameraDescription> cameras) async {
    for (final description in cameras) {
      try {
        final covered = await _probeCameraCoverage(description);
        if (covered) return _LockResult.success(description);
      } on CameraException catch (e) {
        nlog('CameraException probing ${description.name}: ${e.code} ${e.description}');
        return _LockResult.failure(
          CameraPpgError.fromCameraErrorCode(e.code, description: e.description),
        );
      }
    }
    return _LockResult.failure(CameraPpgError.noFinger());
  }

  /// Opens [description] at low resolution with torch on, discards frames
  /// during [_probeWarmUp], then evaluates covered-frame fraction over
  /// [_probeDwell]. Returns `true` when that fraction meets
  /// [_coverageThreshold]. Always tears its own controller/stream/service
  /// down before returning or rethrowing — never leaves a persistent handle
  /// open (informational review F8: the locked camera is closed here and
  /// briefly reopened by [start], mirroring the spike; not a leak).
  ///
  /// Coverage discriminator: [FingerPresence.fromRawIntensity] on
  /// `PPGSignal.rawIntensity`, replicating `flutter_ppg`'s internal
  /// finger-presence band without importing its private assessor.
  Future<bool> _probeCameraCoverage(CameraDescription description) async {
    CameraController? controller;
    StreamController<CameraImage>? imageStreamCtrl;
    FlutterPPGService? service;
    StreamSubscription<PPGSignal>? sub;

    try {
      controller = CameraController(
        description,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.torch);

      imageStreamCtrl = StreamController<CameraImage>();
      controller.startImageStream((img) {
        if (imageStreamCtrl?.isClosed != true) {
          imageStreamCtrl?.add(img);
        }
      });

      service = FlutterPPGService(config: const PPGConfig());
      final stopwatch = Stopwatch()..start();
      var framesSeen = 0;
      var coveredCount = 0;

      sub = service.processImageStream(imageStreamCtrl.stream).listen((signal) {
        final elapsed = stopwatch.elapsed;
        if (elapsed < _probeWarmUp) return; // discard settling frames
        if (elapsed >= _probeWarmUp + _probeDwell) return; // dwell closed
        framesSeen++;
        if (FingerPresence.fromRawIntensity(signal.rawIntensity) ==
            FingerPresence.present) {
          coveredCount++;
        }
      });

      await Future.delayed(_probeWarmUp + _probeDwell);
      stopwatch.stop();

      final fraction = framesSeen == 0 ? 0.0 : coveredCount / framesSeen;
      final covered = fraction >= _coverageThreshold;
      nlog(
        '${description.name}: frames=$framesSeen covered=$coveredCount '
        'fraction=${fraction.toStringAsFixed(2)} → '
        '${covered ? "COVERED" : "not covered"}',
      );
      return covered;
    } finally {
      // Tear down before the caller moves to the next sensor — same
      // ordered sequence _release() uses.
      await _tearDownHandles(
        controller: controller,
        imageStreamCtrl: imageStreamCtrl,
        service: service,
        sub: sub,
      );
    }
  }
}

/// Outcome of [CameraPpgSession._lockCoveredCamera]: either the locked
/// [camera] on success, or a typed [error] on failure. Never both.
class _LockResult {
  const _LockResult._({this.camera, this.error});

  const _LockResult.success(CameraDescription camera) : this._(camera: camera);

  const _LockResult.failure(CameraPpgError error) : this._(error: error);

  final CameraDescription? camera;
  final CameraPpgError? error;
}
