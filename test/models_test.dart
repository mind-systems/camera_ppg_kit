import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/camera_ppg_kit.dart';

void main() {
  group('RrInterval', () {
    test('constructs with required fields and defaults isArtifact to false', () {
      final timestamp = DateTime(2026, 6, 21, 12, 0, 0);
      final interval = RrInterval(intervalMs: 800, timestamp: timestamp);

      expect(interval.intervalMs, 800);
      expect(interval.timestamp, timestamp);
      expect(interval.isArtifact, isFalse);
    });

    test('constructs with isArtifact explicitly set to true', () {
      final timestamp = DateTime(2026, 6, 21, 12, 0, 1);
      final interval = RrInterval(
        intervalMs: 750,
        timestamp: timestamp,
        isArtifact: true,
      );

      expect(interval.intervalMs, 750);
      expect(interval.timestamp, timestamp);
      expect(interval.isArtifact, isTrue);
    });
  });

  group('SignalQuality.fromSnr', () {
    test('returns fair at the good threshold (5.0) and good strictly above it', () {
      expect(SignalQuality.fromSnr(5.0), SignalQuality.fair);
      expect(SignalQuality.fromSnr(5.1), SignalQuality.good);
    });

    test('returns fair just below the good threshold', () {
      expect(SignalQuality.fromSnr(4.9), SignalQuality.fair);
    });

    test('returns poor at the fair threshold (0.0) and fair strictly above it', () {
      expect(SignalQuality.fromSnr(0.0), SignalQuality.poor);
      expect(SignalQuality.fromSnr(0.1), SignalQuality.fair);
    });

    test('returns poor just below the fair threshold', () {
      expect(SignalQuality.fromSnr(-0.1), SignalQuality.poor);
    });

    test('returns poor for negative SNR', () {
      expect(SignalQuality.fromSnr(-10.0), SignalQuality.poor);
    });

    test('returns poor for NaN SNR', () {
      expect(SignalQuality.fromSnr(double.nan), SignalQuality.poor);
    });
  });

  group('MeasurementState', () {
    test('has exactly the four expected lifecycle values', () {
      expect(MeasurementState.values, [
        MeasurementState.idle,
        MeasurementState.warmup,
        MeasurementState.measuring,
        MeasurementState.poorSignal,
      ]);
    });
  });

  group('FingerPresence.fromRawIntensity', () {
    test('returns absent below the dark floor', () {
      expect(FingerPresence.fromRawIntensity(10.0), FingerPresence.absent);
    });

    test('returns absent exactly at the dark floor (30.0)', () {
      expect(FingerPresence.fromRawIntensity(30.0), FingerPresence.absent);
    });

    test('returns present just above the dark floor', () {
      expect(FingerPresence.fromRawIntensity(30.1), FingerPresence.present);
    });

    test('returns present mid-band', () {
      expect(FingerPresence.fromRawIntensity(140.0), FingerPresence.present);
    });

    test('returns present just below the over-bright ceiling', () {
      expect(FingerPresence.fromRawIntensity(249.9), FingerPresence.present);
    });

    test('returns overBright exactly at the over-bright ceiling (250.0)', () {
      expect(
        FingerPresence.fromRawIntensity(250.0),
        FingerPresence.overBright,
      );
    });

    test('returns overBright above the over-bright ceiling', () {
      expect(
        FingerPresence.fromRawIntensity(300.0),
        FingerPresence.overBright,
      );
    });

    test('returns absent for NaN', () {
      expect(
        FingerPresence.fromRawIntensity(double.nan),
        FingerPresence.absent,
      );
    });
  });

  group('CameraPpgError', () {
    test('permissionDenied sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.permissionDenied();

      expect(error.type, CameraPpgErrorType.permissionDenied);
      expect(error.permanentlyDenied, isFalse);
    });

    test('permissionDenied can be constructed as permanently denied', () {
      final error = CameraPpgError.permissionDenied(permanentlyDenied: true);

      expect(error.type, CameraPpgErrorType.permissionDenied);
      expect(error.permanentlyDenied, isTrue);
    });

    test('cameraUnavailable sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.cameraUnavailable();

      expect(error.type, CameraPpgErrorType.cameraUnavailable);
      expect(error.permanentlyDenied, isFalse);
    });

    test('torchUnavailable sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.torchUnavailable();

      expect(error.type, CameraPpgErrorType.torchUnavailable);
      expect(error.permanentlyDenied, isFalse);
    });

    test('unsupportedDevice sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.unsupportedDevice();

      expect(error.type, CameraPpgErrorType.unsupportedDevice);
      expect(error.permanentlyDenied, isFalse);
    });

    test('noFinger sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.noFinger();

      expect(error.type, CameraPpgErrorType.noFinger);
      expect(error.permanentlyDenied, isFalse);
    });

    test('poorSignal sets type and defaults permanentlyDenied to false', () {
      final error = CameraPpgError.poorSignal();

      expect(error.type, CameraPpgErrorType.poorSignal);
      expect(error.permanentlyDenied, isFalse);
    });

    test('fromCameraErrorCode maps CameraAccessDenied to permissionDenied', () {
      final error = CameraPpgError.fromCameraErrorCode('CameraAccessDenied');

      expect(error.type, CameraPpgErrorType.permissionDenied);
      expect(error.permanentlyDenied, isFalse);
    });

    test(
      'fromCameraErrorCode maps CameraAccessDeniedWithoutPrompt to '
      'permissionDenied with permanentlyDenied true',
      () {
        final error = CameraPpgError.fromCameraErrorCode(
          'CameraAccessDeniedWithoutPrompt',
        );

        expect(error.type, CameraPpgErrorType.permissionDenied);
        expect(error.permanentlyDenied, isTrue);
      },
    );

    test(
      'fromCameraErrorCode maps an unknown code to cameraUnavailable '
      'carrying the raw code in message',
      () {
        final error = CameraPpgError.fromCameraErrorCode('SomeWeirdCode');

        expect(error.type, CameraPpgErrorType.cameraUnavailable);
        expect(error.message, 'SomeWeirdCode');
      },
    );
  });
}
