import 'dart:isolate';

/// A single camera plane's bytes plus the metadata needed to rebuild a
/// `Plane` on the receiving side of the frame isolate.
///
/// Pure sendable data — no `camera` import (ARCHITECTURE.md dependency rule
/// 4). [FramePlane.bytes] is wrapped as [TransferableTypedData] by the
/// producer (`frame_isolate.dart`'s `frameMessageFromCameraImage`) so the
/// bytes transfer/materialize cheaply across the isolate port instead of
/// being copied a second time.
class FramePlane {
  const FramePlane({
    required this.bytes,
    required this.targetIndex,
    required this.bytesPerRow,
    this.bytesPerPixel,
    this.width,
    this.height,
  });

  /// Plane bytes, transferred across the isolate port.
  final TransferableTypedData bytes;

  /// The index this plane must occupy in the rebuilt `CameraImage.planes`
  /// list. `extractRedChannel` reads only planes 0 (Y or the single
  /// bgra8888 plane) and 2 (V) — yuv420 ships Y at 0 and V at 2, skipping
  /// the unused U/index 1 entirely; bgra8888 ships one plane at 0. The
  /// receiver (`cameraImageFromFrameMessage`) fills any gap with a cheap
  /// placeholder so the rebuilt list has the right length.
  final int targetIndex;

  /// The row stride for this color plane, in bytes. Required — `Plane`'s
  /// platform-data constructor casts this as a non-null `int`.
  final int bytesPerRow;

  /// The distance between adjacent pixel samples on Android, in bytes.
  /// `null` on iOS.
  final int? bytesPerPixel;

  /// Width of the pixel buffer on iOS. `null` on Android.
  final int? width;

  /// Height of the pixel buffer on iOS. `null` on Android.
  final int? height;
}

/// Sendable snapshot of the plane bytes `SignalProcessor.extractRedChannel`
/// needs, plus the frame metadata required to rebuild a `CameraImage` on the
/// isolate side (see `frame_isolate.dart`).
///
/// Carries only the planes actually used by the reduction — bgra8888 ships
/// one, yuv420 ships two (Y, V) — never the full `CameraImage`, which is not
/// sendable across an isolate port.
class FrameMessage {
  const FrameMessage({
    required this.planes,
    required this.width,
    required this.height,
    required this.format,
  });

  final List<FramePlane> planes;
  final int width;
  final int height;

  /// Raw platform format code (`CameraImage.format.raw`) — Android yuv420 =
  /// 35, iOS bgra8888 = 1111970369 — so the isolate side's
  /// `_asImageFormatGroup` resolves the same `ImageFormatGroup` without this
  /// file needing a `camera` import.
  final int format;
}

/// Sendable snapshot of the `PPGSignal` fields `CameraPpgSession._onSignal`
/// consumes — nothing else, and never the `PPGSignal` object itself, which
/// is not sendable across an isolate port.
class SignalMessage {
  const SignalMessage({
    required this.rrIntervals,
    required this.snr,
    required this.rawIntensity,
    required this.filteredIntensity,
    required this.timestampMicros,
  }) : error = null;

  /// Isolate-side failures cross as data, not thrown exceptions — mirrors
  /// the kit's no-exceptions-across-the-boundary rule (ARCHITECTURE.md key
  /// principle 3). Every other field is meaningless when this constructor is
  /// used; callers must check [isError] first.
  const SignalMessage.error(this.error)
      : rrIntervals = const [],
        snr = 0.0,
        rawIntensity = 0.0,
        filteredIntensity = 0.0,
        timestampMicros = 0;

  final List<double> rrIntervals;
  final double snr;
  final double rawIntensity;
  final double filteredIntensity;

  /// Microseconds since epoch — sendable stand-in for `PPGSignal.timestamp`
  /// (`DateTime` itself is sendable, but the plain `int` keeps this type
  /// free of any doubt about isolate-boundary sendability).
  final int timestampMicros;

  /// Non-null when this message represents an isolate-side failure rather
  /// than a real signal.
  final String? error;

  bool get isError => error != null;
}
