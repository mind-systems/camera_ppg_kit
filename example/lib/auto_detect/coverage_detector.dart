import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

import '../common/finger_presence.dart';
import 'auto_detect_result.dart';
import 'camera_probe.dart';
import 'log.dart';

/// Runs a sequential coverage round-trip over [cameras] and returns the
/// first sensor whose finger-presence test passes during the dwell window.
///
/// The finger must be placed **before** calling this function — this is a
/// one-shot pass, not a polling loop.
///
/// Coverage discriminator: rawIntensity is within [PPGConfig.fingerPresenceMin]
/// and [PPGConfig.fingerPresenceMax]. This replicates what SignalQualityAssessor
/// does internally; we do NOT import that private class.
///
/// [warmUp]  — frames received during this window are discarded to let torch
///             exposure settle. The listener is attached immediately to avoid
///             buffering the non-broadcast StreamController.
/// [dwell]   — window (after warm-up) over which covered-frame fraction is
///             evaluated. Threshold: covered-fraction ≥ 0.6.
Future<CoverageOutcome> detectCoveredCamera(
  List<RearCamera> cameras, {
  Duration warmUp = const Duration(milliseconds: 400),
  Duration dwell = const Duration(milliseconds: 700),
}) async {
  const cfg = PPGConfig();

  final records = <CameraProbeRecord>[];

  for (final cam in cameras) {
    ppgLog('Probing ${cam.name} (index ${cam.index}, lensType: ${cam.lensType})');

    CameraController? controller;
    StreamController<CameraImage>? imageStreamCtrl;
    FlutterPPGService? service;
    StreamSubscription<PPGSignal>? sub;

    try {
      // ── open camera ──────────────────────────────────────────────────────
      controller = CameraController(
        cam.description,
        ResolutionPreset.low,
        enableAudio: false,
        // iOS expects bgra8888; Android expects yuv420. Using the platform
        // default (null) lets the camera plugin pick the native format —
        // flutter_ppg's red-channel extractor handles both.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.torch);

      // ── bridge startImageStream → Stream<CameraImage> ────────────────────
      // L1: use ?. on the captured variable — teardown nulls it before the
      // stream fully drains, and a late frame callback must not crash.
      imageStreamCtrl = StreamController<CameraImage>();
      controller.startImageStream((img) {
        if (imageStreamCtrl?.isClosed != true) {
          imageStreamCtrl?.add(img);
        }
      });

      // ── attach listener immediately (M1 fix) ─────────────────────────────
      // Attaching after a Future.delayed(warmUp) leaves imageStreamCtrl as a
      // non-broadcast StreamController with no reader: frames emitted during
      // warm-up are buffered and replayed in a burst when listen is called,
      // corrupting the count and the flutter_ppg FPS detector.
      // Instead, listen immediately and skip frames by elapsed time.
      service = FlutterPPGService(config: cfg);
      final stopwatch = Stopwatch()..start();
      int framesSeen = 0;
      int coveredCount = 0;

      sub = service.processImageStream(imageStreamCtrl.stream).listen((signal) {
        final elapsed = stopwatch.elapsed;
        if (elapsed < warmUp) return; // discard torch/exposure-settling frames
        if (elapsed >= warmUp + dwell) return; // dwell window already closed
        framesSeen++;
        if (isFingerPresent(signal.rawIntensity, config: cfg)) coveredCount++;
      });

      // ── wait for the full warm-up + dwell window ─────────────────────────
      await Future.delayed(warmUp + dwell);
      stopwatch.stop();

      final fraction = framesSeen == 0 ? 0.0 : coveredCount / framesSeen;
      final isCovered = fraction >= 0.6;

      ppgLog(
        '${cam.name}: frames=$framesSeen covered=$coveredCount '
        'fraction=${fraction.toStringAsFixed(2)} → ${isCovered ? "COVERED" : "not covered"}',
      );

      records.add(CameraProbeRecord(
        camera: cam,
        framesSeen: framesSeen,
        coveredFrames: coveredCount,
        covered: isCovered,
      ));

      // ── tear down before moving to the next camera ────────────────────────
      await _tearDown(
        controller: controller,
        imageStreamCtrl: imageStreamCtrl,
        service: service,
        sub: sub,
      );
      controller = null;
      imageStreamCtrl = null;
      service = null;
      sub = null;

      if (isCovered) {
        return CoverageOutcome.success(lockedCamera: cam, records: records);
      }
    } on CameraException catch (e, st) {
      ppgLog('CameraException on ${cam.name}: ${e.code} ${e.description}',
          error: e, stackTrace: st);

      await _tearDown(
        controller: controller,
        imageStreamCtrl: imageStreamCtrl,
        service: service,
        sub: sub,
      );
      controller = null;
      imageStreamCtrl = null;
      service = null;
      sub = null;

      // Permission denial surfaces as a CameraException with specific codes.
      final code = e.code.toLowerCase();
      if (code.contains('permission') || code.contains('access')) {
        return CoverageOutcome.failure(
          error: AutoDetectError.permissionDenied,
          records: records,
        );
      }
      return CoverageOutcome.failure(
        error: AutoDetectError.cameraError,
        records: records,
      );
    } catch (e, st) {
      ppgLog('Unexpected error on ${cam.name}', error: e, stackTrace: st);
      await _tearDown(
        controller: controller,
        imageStreamCtrl: imageStreamCtrl,
        service: service,
        sub: sub,
      );
      return CoverageOutcome.failure(
        error: AutoDetectError.cameraError,
        records: records,
      );
    }
  }

  return CoverageOutcome.failure(
    error: AutoDetectError.noCoveredCamera,
    records: records,
  );
}

/// Tears down all camera resources in the correct order, tolerating nulls.
///
/// Order: stop image stream → close input StreamController → cancel signal
/// subscription → dispose service → set flash off → dispose controller.
/// The input controller is closed before the subscription is cancelled to
/// avoid deadlocking flutter_ppg's `async*` generator (see step 2 below).
/// Never holds two controllers open at once.
Future<void> _tearDown({
  required CameraController? controller,
  required StreamController<CameraImage>? imageStreamCtrl,
  required FlutterPPGService? service,
  required StreamSubscription<PPGSignal>? sub,
}) async {
  // 1. Stop the camera image stream (callbacks may still fire briefly after).
  if (controller != null && controller.value.isStreamingImages) {
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  // 2. Close the input bridge BEFORE cancelling the subscription.
  //
  // flutter_ppg's processImageStream is an `async*` generator parked on
  // `await for (image in images)`. Cancelling the subscription while the input
  // controller is still open deadlocks: the generator is suspended waiting for
  // either the next frame (the camera is already stopped — none coming) or the
  // input to close (still open at this point), so it never reaches a point
  // where the cancel can unwind it. Closing the input ends the await-for, the
  // generator completes and emits done, and step 3's cancel returns at once.
  await imageStreamCtrl?.close();

  // 3. Cancel the PPG signal subscription (completes promptly now).
  await sub?.cancel();

  // 4. Dispose the PPG service.
  service?.dispose();

  // 5. Turn torch off before disposing the controller.
  if (controller != null && controller.value.isInitialized) {
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  // 6. Dispose the camera controller.
  await controller?.dispose();
}
