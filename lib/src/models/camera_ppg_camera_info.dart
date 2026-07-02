import 'package:flutter/foundation.dart';

/// Descriptive metadata for one selectable rear-facing camera, returned by
/// `CameraPpgSession.availableCameras()`.
///
/// This is diagnostics/override data only — the host reads it for display
/// (e.g. a settings picker) and to choose an id for
/// `CameraPpgSession.useCamera(id)`. The kit itself never uses these fields
/// to select a sensor: normal operation is the signal-based auto-detect
/// round-trip, not this metadata.
///
/// Fields are kept as plain, permissive values (a string `lensType`, not an
/// enum) rather than a closed type, so a lens category future devices report
/// that this kit doesn't yet recognize still decodes instead of breaking.
@immutable
class CameraPpgCameraInfo {
  const CameraPpgCameraInfo({
    required this.id,
    required this.lensType,
    required this.flashAvailable,
  });

  /// Selection key — pass this to `CameraPpgSession.useCamera(id)`. Equal to
  /// the underlying `CameraDescription.name`.
  final String id;

  /// Coarse lens category as reported by the platform (e.g. `wide`,
  /// `telephoto`, `ultraWide`, or `unknown`). Descriptive only — see
  /// class doc.
  final String lensType;

  /// Whether this camera has a usable flash/torch alongside it.
  ///
  /// This kit always runs the torch on the rear camera during capture, but
  /// the underlying `CameraDescription` exposes no flash-capability
  /// property to probe, and probing it would require opening a controller
  /// (out of scope for a read-only enumeration). This is therefore a
  /// documented constant `true` for every rear entry — an unverified
  /// rear+torch assumption, not a probed capability — and must never be
  /// used to select or gate a camera.
  final bool flashAvailable;
}
