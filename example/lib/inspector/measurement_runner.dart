import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

import '../auto_detect/camera_probe.dart';
import '../auto_detect/log.dart';
import '../common/fps_meter.dart';

/// Owns a single continuous PPG capture session on a given [RearCamera].
///
/// Runs a raw passthrough harness: no acceptance policy, no warm-up window,
/// no session lifecycle. Every [PPGSignal] emitted by [FlutterPPGService] is
/// forwarded on [signals] as-is.
///
/// Usage:
/// ```dart
/// final runner = MeasurementRunner();
/// await runner.start(camera);
/// runner.signals.listen((signal) { ... });
/// // later:
/// await runner.stop();
/// ```
class MeasurementRunner {
  CameraController? _controller;
  StreamController<CameraImage>? _imageStreamCtrl;
  FlutterPPGService? _service;
  StreamSubscription<PPGSignal>? _sub;
  StreamController<PPGSignal>? _signalsCtrl;

  final FpsMeter _fpsMeter = FpsMeter();

  /// Broadcast stream of raw [PPGSignal] output.
  ///
  /// Subscribe after [start] returns. Before [start] is called, [_signalsCtrl]
  /// is null and the getter returns [Stream.empty], which closes immediately
  /// with no data.
  Stream<PPGSignal> get signals =>
      _signalsCtrl?.stream ?? const Stream.empty();

  /// Rolling sustained frame-arrival rate over the [FpsMeter] window.
  ///
  /// Measured independently of [PPGSignal.frameRate] — this is the actual
  /// delivery rate to the signal listener, which degrades under heavy UI load.
  double get sustainedFps => _fpsMeter.fps;

  /// Opens [camera] at low resolution with torch on, locks exposure and focus
  /// (best-effort — not all platforms support locking), then starts feeding
  /// [CameraImage] frames through [FlutterPPGService].
  ///
  /// Camera-open failures are logged without throwing; [signals] stays idle.
  ///
  /// Calling [start] twice without an intervening [stop] is a no-op: the guard
  /// prevents the first session from being orphaned with a leaked controller.
  Future<void> start(RearCamera camera) async {
    if (_signalsCtrl != null) return;
    _signalsCtrl = StreamController<PPGSignal>.broadcast();

    try {
      const cfg = PPGConfig();

      _controller = CameraController(
        camera.description,
        ResolutionPreset.low,
        enableAudio: false,
        // iOS expects bgra8888; Android expects yuv420.
        // Matches the platform selection used in coverage_detector.dart.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.torch);

      // Best-effort exposure lock — auto-exposure chases and flattens the PPG
      // signal; locking it improves signal stability on supported platforms.
      try {
        await _controller!.setExposureMode(ExposureMode.locked);
      } catch (e) {
        ppgLog('setExposureMode(locked) not supported on this platform: $e');
      }

      // Best-effort focus lock — not critical for PPG but eliminates micro-
      // adjustments that can momentarily vary red-channel intensity.
      try {
        await _controller!.setFocusMode(FocusMode.locked);
      } catch (e) {
        ppgLog('setFocusMode(locked) not supported on this platform: $e');
      }

      // Bridge startImageStream → StreamController<CameraImage>.
      // Use ?. on the captured variable — teardown nulls it before the stream
      // fully drains, and a late frame callback must not crash (L1 pattern).
      _imageStreamCtrl = StreamController<CameraImage>();
      _controller!.startImageStream((img) {
        if (_imageStreamCtrl?.isClosed != true) {
          _imageStreamCtrl?.add(img);
        }
      });

      _service = FlutterPPGService(config: cfg);

      _sub = _service!
          .processImageStream(_imageStreamCtrl!.stream)
          .listen(
            (signal) {
              _fpsMeter.record(DateTime.now());
              if (_signalsCtrl?.isClosed != true) {
                _signalsCtrl?.add(signal);
              }
            },
            onError: (Object e, StackTrace st) {
              ppgLog('PPGService stream error', error: e, stackTrace: st);
            },
          );

      ppgLog('MeasurementRunner started on ${camera.name}');
    } on CameraException catch (e, st) {
      ppgLog(
        'CameraException starting runner on ${camera.name}: '
        '${e.code} ${e.description}',
        error: e,
        stackTrace: st,
      );
      // Do not rethrow — signals remains idle, UI shows no data.
    } catch (e, st) {
      ppgLog(
        'Unexpected error starting runner on ${camera.name}',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Tears down all camera resources. Safe to call twice (idempotent).
  ///
  /// Teardown order mirrors `coverage_detector.dart`:
  /// 1. stop image stream
  /// 2. cancel signal subscription
  /// 3. dispose PPG service
  /// 4. close image-stream bridge
  /// 5. torch off
  /// 6. dispose camera controller
  /// 7. close signals stream
  Future<void> stop() async {
    ppgLog('MeasurementRunner stopping');

    // Capture and clear all fields atomically so re-entrant calls are no-ops.
    final ctrl = _controller;
    final imgCtrl = _imageStreamCtrl;
    final service = _service;
    final sub = _sub;
    final signalsCtrl = _signalsCtrl;

    _controller = null;
    _imageStreamCtrl = null;
    _service = null;
    _sub = null;
    _signalsCtrl = null;

    // 1. Stop the camera image stream.
    if (ctrl != null && ctrl.value.isStreamingImages) {
      try {
        await ctrl.stopImageStream();
      } catch (_) {}
    }

    // 2. Cancel the PPG signal subscription.
    await sub?.cancel();

    // 3. Dispose the PPG service.
    service?.dispose();

    // 4. Close the image-stream bridge (no more frames after this).
    await imgCtrl?.close();

    // 5. Turn torch off before disposing the controller.
    if (ctrl != null && ctrl.value.isInitialized) {
      try {
        await ctrl.setFlashMode(FlashMode.off);
      } catch (_) {}
    }

    // 6. Dispose the camera controller.
    await ctrl?.dispose();

    // 7. Close the signals broadcast stream.
    await signalsCtrl?.close();

    ppgLog('MeasurementRunner stopped');
  }
}
