import 'package:flutter/foundation.dart';

/// Typed category of a [CameraPpgError].
enum CameraPpgErrorType {
  /// The user has not granted camera permission, or has permanently
  /// denied it (see [CameraPpgError.permanentlyDenied]).
  permissionDenied,

  /// The camera hardware could not be opened or used.
  cameraUnavailable,

  /// The torch (flash) could not be enabled or controlled.
  torchUnavailable,

  /// The device is on a data-driven deny-list of devices known not to
  /// support contact-PPG measurement (e.g. no usable torch/lens pairing).
  unsupportedDevice,

  /// No finger was detected covering the lens and torch.
  noFinger,

  /// Signal quality is too poor to trust RR intervals.
  poorSignal,
}

/// Typed, never-thrown error value crossing the kit's API boundary.
///
/// Modeled on `neiry_kit`'s `NeiryError` for cross-kit consistency. Unlike
/// `NeiryError`, this type is never wrapped in an exception and thrown
/// across a channel — expected failure states (permission denial, no
/// finger, poor signal, unsupported device) are returned as plain values,
/// per the kit's "no exceptions across the boundary" rule.
@immutable
class CameraPpgError {
  const CameraPpgError._({
    required this.type,
    this.permanentlyDenied = false,
    this.message,
  });

  /// The category of failure.
  final CameraPpgErrorType type;

  /// Only meaningful when [type] is [CameraPpgErrorType.permissionDenied].
  ///
  /// `true` when the platform reports the denial as permanent (e.g. iOS
  /// "restricted" or a prior "don't ask again" on Android) — the UI should
  /// route the user to app settings rather than re-prompting in place.
  final bool permanentlyDenied;

  /// Optional human-readable / diagnostic detail (e.g. the raw platform
  /// error code when it did not map to a more specific [type]).
  final String? message;

  /// Camera permission was denied.
  factory CameraPpgError.permissionDenied({
    bool permanentlyDenied = false,
    String? message,
  }) {
    return CameraPpgError._(
      type: CameraPpgErrorType.permissionDenied,
      permanentlyDenied: permanentlyDenied,
      message: message,
    );
  }

  /// The camera hardware could not be opened or used.
  factory CameraPpgError.cameraUnavailable({String? message}) {
    return CameraPpgError._(
      type: CameraPpgErrorType.cameraUnavailable,
      message: message,
    );
  }

  /// The torch (flash) could not be enabled or controlled.
  factory CameraPpgError.torchUnavailable({String? message}) {
    return CameraPpgError._(
      type: CameraPpgErrorType.torchUnavailable,
      message: message,
    );
  }

  /// The device is on the (data-driven) deny-list of unsupported devices.
  factory CameraPpgError.unsupportedDevice({String? message}) {
    return CameraPpgError._(
      type: CameraPpgErrorType.unsupportedDevice,
      message: message,
    );
  }

  /// No finger was detected covering the lens and torch.
  factory CameraPpgError.noFinger({String? message}) {
    return CameraPpgError._(
      type: CameraPpgErrorType.noFinger,
      message: message,
    );
  }

  /// Signal quality is too poor to trust RR intervals.
  factory CameraPpgError.poorSignal({String? message}) {
    return CameraPpgError._(
      type: CameraPpgErrorType.poorSignal,
      message: message,
    );
  }

  /// Maps a `package:camera` `CameraException.code` (and optional
  /// `description`) onto a [CameraPpgError].
  ///
  /// The kit has no native channel of its own (confirmed by the Phase-2
  /// spike), so there is no map payload to deserialize — the `camera`
  /// plugin surfaces failures as `CameraException(String code, String?
  /// description)` instead. The later API layer calls this at the
  /// `CameraException` catch site.
  ///
  /// - `CameraAccessDenied` → [permissionDenied].
  /// - `CameraAccessDeniedWithoutPrompt` (Android "don't ask again") or a
  ///   restricted-access code (iOS parental/MDM restriction) →
  ///   [permissionDenied] with [permanentlyDenied] set.
  /// - Any other recognized torch- or camera-unavailable code →
  ///   [torchUnavailable] / [cameraUnavailable] respectively.
  /// - An unrecognized code → [cameraUnavailable], carrying the raw [code]
  ///   in [message] so it is not silently lost.
  factory CameraPpgError.fromCameraErrorCode(
    String code, {
    String? description,
  }) {
    switch (code) {
      case 'CameraAccessDenied':
        return CameraPpgError.permissionDenied(message: description);
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return CameraPpgError.permissionDenied(
          permanentlyDenied: true,
          message: description,
        );
      case 'torchUnavailable':
      case 'setFlashModeFailed':
        return CameraPpgError.torchUnavailable(message: description);
      case 'cameraNotFound':
      case 'CameraNotFound':
        return CameraPpgError.cameraUnavailable(message: description);
      default:
        return CameraPpgError.cameraUnavailable(message: code);
    }
  }
}
