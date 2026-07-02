import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

import '../util/nlog.dart';
import 'frame_message.dart';

/// The isolate-boundary host: spawns and owns the long-lived background
/// isolate that runs `FlutterPPGService` off the UI isolate, plus the
/// `CameraImage` <-> [FrameMessage] adapters that cross its port.
///
/// This is the **sole** `src/processing/` file permitted `camera` /
/// `flutter_ppg` imports (ARCHITECTURE.md dependency rule 4 exception,
/// recorded there) — it is the isolate-boundary host, not general
/// signal-processing logic, and the `CameraController` wiring itself stays
/// in `src/api/` per spec note 13.

// ── Producer side (main/UI isolate) — CameraImage -> FrameMessage ─────────

/// Extracts only the plane(s) `SignalProcessor.extractRedChannel` reads from
/// [image] and wraps them as a [FrameMessage] for the frame isolate.
///
/// Allocation-lean by design — this runs on every frame (24-60x/s) inside
/// `CameraController.startImageStream`'s UI-isolate callback, so it must
/// stay cheap even though the isolate offload moves the heavy DSP work
/// elsewhere.
FrameMessage frameMessageFromCameraImage(CameraImage image) {
  final planes = <FramePlane>[];
  if (image.format.group == ImageFormatGroup.bgra8888) {
    planes.add(_framePlane(image.planes[0], targetIndex: 0));
  } else {
    // yuv420 — extractRedChannel reads planes[0] (Y) and planes[2] (V) only;
    // plane 1 (U) is never sent across the port.
    planes.add(_framePlane(image.planes[0], targetIndex: 0));
    planes.add(_framePlane(image.planes[2], targetIndex: 2));
  }
  return FrameMessage(
    planes: planes,
    width: image.width,
    height: image.height,
    format: image.format.raw as int,
  );
}

FramePlane _framePlane(Plane plane, {required int targetIndex}) => FramePlane(
      bytes: TransferableTypedData.fromList([plane.bytes]),
      targetIndex: targetIndex,
      bytesPerRow: plane.bytesPerRow,
      bytesPerPixel: plane.bytesPerPixel,
      width: plane.width,
      height: plane.height,
    );

// ── Isolate side — FrameMessage -> CameraImage ─────────────────────────────

/// Materializes [message]'s transferred plane bytes and rebuilds a
/// `CameraImage` via the deprecated `CameraImage.fromPlatformData`
/// constructor — the only public (if deprecated) way to construct one from
/// plain data outside the `camera` plugin's own platform-channel path.
///
/// **Plane-index preservation (Android silent-failure trap):** the rebuilt
/// `planes` list must have an entry at every index up to the highest
/// [FramePlane.targetIndex] the message carries — for yuv420 that means a
/// **3-element** list with V at index 2 and a cheap placeholder at index 1
/// (non-null `bytesPerRow`, empty `bytes`; `extractRedChannel` never reads
/// index 1). A 2-element `[Y, V]` list instead makes `extractRedChannel`'s
/// `image.planes[2]` throw a `RangeError` that `flutter_ppg`'s
/// `processImageStream` silently swallows — every Android frame would be
/// skipped with no `PPGSignal` emitted and no error surfaced. Task 1's
/// on-device verdict (note 13) confirms this shape is correct.
CameraImage cameraImageFromFrameMessage(FrameMessage message) {
  final maxIndex = message.planes.fold<int>(
    0,
    (acc, p) => p.targetIndex > acc ? p.targetIndex : acc,
  );
  final byTargetIndex = {for (final p in message.planes) p.targetIndex: p};
  final anyPlane = message.planes.first;

  final planeMaps = <Map<String, dynamic>>[];
  for (var i = 0; i <= maxIndex; i++) {
    final p = byTargetIndex[i];
    if (p != null) {
      planeMaps.add({
        'bytes': p.bytes.materialize().asUint8List(),
        'bytesPerRow': p.bytesPerRow,
        'bytesPerPixel': p.bytesPerPixel,
        'width': p.width,
        'height': p.height,
      });
    } else {
      // Placeholder for an index no plane targets (yuv420's unused U at
      // index 1) — never read by extractRedChannel, but Plane's
      // platform-data constructor requires a non-null bytesPerRow.
      planeMaps.add({
        'bytes': Uint8List(0),
        'bytesPerRow': anyPlane.bytesPerRow,
        'bytesPerPixel': anyPlane.bytesPerPixel,
        'width': anyPlane.width,
        'height': anyPlane.height,
      });
    }
  }

  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'width': message.width,
    'height': message.height,
    'format': message.format,
    'planes': planeMaps,
  });
}

// ── Long-lived isolate host ────────────────────────────────────────────────

const _stopSentinel = '__frame_isolate_stop__';
const _stoppedSentinel = '__frame_isolate_stopped__';

/// Owns one long-lived background isolate for the duration of a measurement
/// — spawned once by `start()`, never per frame (`Isolate.run` would
/// re-spawn 24-60x/s). Runs `FlutterPPGService` entirely inside that
/// isolate: [sink] feeds reconstructed `CameraImage`s in, [signals] streams
/// [SignalMessage]s back out.
class FrameIsolate {
  FrameIsolate._(
    this._isolate,
    this._toIsolate,
    this._fromIsolate,
    this._signalsController,
    this._stopAck,
  );

  final Isolate _isolate;
  final SendPort _toIsolate;
  final ReceivePort _fromIsolate;
  final StreamController<SignalMessage> _signalsController;
  final Completer<void> _stopAck;

  /// Broadcast stream of signals produced inside the isolate — narrowed to
  /// [SignalMessage] at the boundary; never `PPGSignal`.
  Stream<SignalMessage> get signals => _signalsController.stream;

  /// Spawns the isolate and completes once the `SendPort` handshake is
  /// done, so [sink] is safe to call immediately after this returns.
  static Future<FrameIsolate> spawn() async {
    final fromIsolate = ReceivePort();
    final handshake = Completer<SendPort>();
    final stopAck = Completer<void>();
    final signalsController = StreamController<SignalMessage>.broadcast();

    fromIsolate.listen((dynamic message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      if (message == _stoppedSentinel) {
        if (!stopAck.isCompleted) stopAck.complete();
        return;
      }
      if (message is SignalMessage) {
        if (!signalsController.isClosed) signalsController.add(message);
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _frameIsolateEntrypoint,
        fromIsolate.sendPort,
        debugName: 'camera_ppg_kit-frame-isolate',
      );

      final toIsolate = await handshake.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError('frame isolate handshake timed out'),
      );

      nlog('frame isolate spawned + handshake complete');
      return FrameIsolate._(
        isolate,
        toIsolate,
        fromIsolate,
        signalsController,
        stopAck,
      );
    } catch (e) {
      // Spawn or handshake failed — reclaim whatever was already opened so a
      // wedged/slow spawn (or handshake timeout) can't strand a zombie
      // isolate + open port (review round-2 Finding 1).
      isolate?.kill(priority: Isolate.immediate);
      fromIsolate.close();
      await signalsController.close();
      rethrow;
    }
  }

  /// Feeds one frame into the isolate. Fire-and-forget, mirroring today's
  /// `imageStreamCtrl.add(img)` bridge — no backpressure is applied.
  void sink(FrameMessage message) => _toIsolate.send(message);

  /// Tears the isolate down: signals it to run its own close-before-cancel
  /// teardown (mirroring `_tearDownHandles`' invariant *inside* the
  /// isolate — closing the `CameraImage` controller before cancelling the
  /// `PPGSignal` subscription, since `processImageStream` is an `async*`
  /// generator parked on `await for`), waits briefly for its ack, then kills
  /// the isolate outright. Idempotent-safe to call once; the caller (session
  /// teardown) owns not calling it twice.
  Future<void> dispose() async {
    _toIsolate.send(_stopSentinel);
    await _stopAck.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => nlog('frame isolate stop ack timed out — killing anyway'),
    );
    _isolate.kill(priority: Isolate.immediate);
    _fromIsolate.close();
    await _signalsController.close();
    nlog('frame isolate disposed');
  }
}

/// Isolate-side entrypoint: reconstructs `CameraImage`s from incoming
/// [FrameMessage]s, drives a real `FlutterPPGService` entirely inside this
/// isolate, and replies with [SignalMessage]s — errors cross as data
/// ([SignalMessage.error]), never as thrown exceptions across the port.
void _frameIsolateEntrypoint(SendPort mainSendPort) {
  final inbound = ReceivePort();
  mainSendPort.send(inbound.sendPort);

  final service = FlutterPPGService(config: const PPGConfig());
  final imageStreamCtrl = StreamController<CameraImage>();

  final sub = service.processImageStream(imageStreamCtrl.stream).listen(
    (signal) {
      mainSendPort.send(SignalMessage(
        rrIntervals: signal.rrIntervals,
        snr: signal.snr,
        rawIntensity: signal.rawIntensity,
        filteredIntensity: signal.filteredIntensity,
        timestampMicros: signal.timestamp.microsecondsSinceEpoch,
      ));
    },
    onError: (Object e, StackTrace st) {
      mainSendPort.send(SignalMessage.error('$e'));
    },
  );

  inbound.listen((dynamic message) async {
    if (message == _stopSentinel) {
      // Close-before-cancel invariant, mirrored inside the isolate: cancel
      // first while processImageStream's `await for` is still parked on an
      // open input deadlocks it.
      await imageStreamCtrl.close();
      await sub.cancel();
      service.dispose();
      mainSendPort.send(_stoppedSentinel);
      inbound.close();
      return;
    }
    if (message is FrameMessage) {
      try {
        final image = cameraImageFromFrameMessage(message);
        if (!imageStreamCtrl.isClosed) imageStreamCtrl.add(image);
      } catch (e) {
        mainSendPort.send(SignalMessage.error('frame reconstruct failed: $e'));
      }
    }
  });
}
