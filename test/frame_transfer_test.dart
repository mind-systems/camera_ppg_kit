import 'package:camera/camera.dart';
import 'package:camera_ppg_kit/src/processing/frame_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Raw platform format codes (see frame_isolate.dart's docs / plan recon):
// Android yuv420 = 35, iOS bgra8888 = 1111970369.
const _androidYuv420 = 35;
const _iosBgra8888 = 1111970369;

void main() {
  // `CameraImage.fromPlatformData`'s ImageFormat resolves `format.group`
  // from `defaultTargetPlatform` at *construction* time — and Flutter's test
  // environment defaults that to TargetPlatform.android regardless of host
  // platform, so bgra8888 (iOS) round-trips need an explicit override.
  group('bgra8888 (iOS)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('single-plane round-trips and reproduces the red-channel mean', () {
      // 2x2 pixel bgra8888 image: 4 bytes/pixel (B, G, R, A).
      final bytes = Uint8List.fromList([
        10, 20, 30, 255, // pixel 0: R=30
        40, 50, 60, 255, // pixel 1: R=60
        70, 80, 90, 255, // pixel 2: R=90
        100, 110, 120, 255, // pixel 3: R=120
      ]);
      final image = _bgra8888Image(bytes, width: 2, height: 2, bytesPerRow: 8);

      final message = frameMessageFromCameraImage(image);
      expect(message.format, _iosBgra8888);
      expect(message.planes, hasLength(1));
      expect(message.planes.single.targetIndex, 0);

      final rebuilt = cameraImageFromFrameMessage(message);
      expect(rebuilt.format.raw, _iosBgra8888);
      expect(rebuilt.format.group, ImageFormatGroup.bgra8888);
      expect(rebuilt.width, 2);
      expect(rebuilt.height, 2);
      expect(rebuilt.planes, hasLength(1));
      expect(rebuilt.planes[0].bytes, bytes);

      final expectedMean = _bgra8888RedMean(bytes);
      expect(expectedMean, (30 + 60 + 90 + 120) / 4);
      expect(_bgra8888RedMean(rebuilt.planes[0].bytes), expectedMean);
    });

    test('empty plane bytes round-trip without throwing', () {
      final bytes = Uint8List(0);
      final image = _bgra8888Image(bytes, width: 0, height: 0, bytesPerRow: 0);

      final message = frameMessageFromCameraImage(image);
      final rebuilt = cameraImageFromFrameMessage(message);

      expect(rebuilt.planes.single.bytes, isEmpty);
      expect(_bgra8888RedMean(rebuilt.planes.single.bytes), 0.0);
    });
  });

  group('yuv420 (Android)', () {
    test('rebuild has 3 planes with V at index 2 and reproduces the red-channel formula', () {
      final yBytes = Uint8List.fromList([100, 110, 120, 130]);
      final vBytes = Uint8List.fromList([140, 150]);
      final image = _yuv420Image(
        yBytes,
        vBytes,
        width: 2,
        height: 2,
        yBytesPerRow: 2,
        vBytesPerRow: 2,
      );

      final message = frameMessageFromCameraImage(image);
      expect(message.format, _androidYuv420);
      // Only Y and V are shipped — U (plane 1) is never read by
      // extractRedChannel, so the producer must not send it.
      expect(message.planes, hasLength(2));
      expect(message.planes[0].targetIndex, 0);
      expect(message.planes[1].targetIndex, 2);

      final rebuilt = cameraImageFromFrameMessage(message);
      expect(rebuilt.format.raw, _androidYuv420);
      expect(rebuilt.format.group, ImageFormatGroup.yuv420);
      // The plane-index trap this locks: a 2-element [Y, V] list makes
      // extractRedChannel's `planes[2]` throw a RangeError that
      // processImageStream silently swallows (note 13 / Task 3) — every
      // Android frame would be skipped with no signal and no error.
      expect(rebuilt.planes, hasLength(3));
      expect(rebuilt.planes[0].bytes, yBytes);
      expect(rebuilt.planes[2].bytes, vBytes);
      // Placeholder at index 1 is never read by extractRedChannel but must
      // still satisfy Plane's non-null bytesPerRow requirement.
      expect(rebuilt.planes[1].bytesPerRow, isNotNull);

      final yMean = (100 + 110 + 120 + 130) / 4;
      final vMean = (140 + 150) / 2;
      final expectedRed = yMean + 1.402 * (vMean - 128);
      expect(
        _yuv420RedMean(rebuilt.planes[0].bytes, rebuilt.planes[2].bytes),
        closeTo(expectedRed, 1e-9),
      );
    });

    test('single-pixel planes round-trip and reproduce the red-channel formula', () {
      final yBytes = Uint8List.fromList([200]);
      final vBytes = Uint8List.fromList([50]);
      final image = _yuv420Image(
        yBytes,
        vBytes,
        width: 1,
        height: 1,
        yBytesPerRow: 1,
        vBytesPerRow: 1,
      );

      final message = frameMessageFromCameraImage(image);
      final rebuilt = cameraImageFromFrameMessage(message);

      expect(rebuilt.planes, hasLength(3));
      expect(rebuilt.planes[0].bytes, yBytes);
      expect(rebuilt.planes[2].bytes, vBytes);
      expect(
        _yuv420RedMean(rebuilt.planes[0].bytes, rebuilt.planes[2].bytes),
        closeTo(200 + 1.402 * (50 - 128), 1e-9),
      );
    });
  });
}

// ── Synthetic CameraImage builders (test-only; use the same deprecated
// fromPlatformData path frame_isolate.dart itself uses on the isolate side,
// so the round-trip is exercised through real camera package code). ───────

CameraImage _bgra8888Image(
  Uint8List bytes, {
  required int width,
  required int height,
  required int bytesPerRow,
}) {
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'width': width,
    'height': height,
    'format': _iosBgra8888,
    'planes': [
      {
        'bytes': bytes,
        'bytesPerRow': bytesPerRow,
        'bytesPerPixel': null,
        'width': width,
        'height': height,
      },
    ],
  });
}

CameraImage _yuv420Image(
  Uint8List yBytes,
  Uint8List vBytes, {
  required int width,
  required int height,
  required int yBytesPerRow,
  required int vBytesPerRow,
}) {
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'width': width,
    'height': height,
    'format': _androidYuv420,
    'planes': [
      {
        'bytes': yBytes,
        'bytesPerRow': yBytesPerRow,
        'bytesPerPixel': 1,
        'width': null,
        'height': null,
      },
      // Real Android yuv420 has a U plane at index 1. frameMessageFromCameraImage
      // never reads it, so a minimal stand-in keeps the synthetic image
      // realistic without asserting anything about its content.
      {
        'bytes': Uint8List(yBytes.length),
        'bytesPerRow': vBytesPerRow,
        'bytesPerPixel': 2,
        'width': null,
        'height': null,
      },
      {
        'bytes': vBytes,
        'bytesPerRow': vBytesPerRow,
        'bytesPerPixel': 2,
        'width': null,
        'height': null,
      },
    ],
  });
}

// ── Reference red-channel formulas — SignalProcessor.extractRedChannel
// lives in flutter_ppg's signal_processor.dart, which the package barrel
// does not export, so it isn't callable from this test. These replicate its
// documented formula instead (Task 7's plan note). ─────────────────────────

double _bgra8888RedMean(Uint8List bytes) {
  if (bytes.isEmpty) return 0.0;
  var sum = 0;
  var count = 0;
  for (var i = 2; i < bytes.length; i += 4) {
    sum += bytes[i];
    count++;
  }
  return count == 0 ? 0.0 : sum / count;
}

double _yuv420RedMean(Uint8List yBytes, Uint8List vBytes) {
  double mean(Uint8List b) {
    if (b.isEmpty) return 0.0;
    var sum = 0;
    for (final v in b) {
      sum += v;
    }
    return sum / b.length;
  }

  return mean(yBytes) + 1.402 * (mean(vBytes) - 128);
}
