
import 'camera_ppg_kit_platform_interface.dart';

export 'src/api/camera_ppg_session.dart';
export 'src/models/camera_ppg_camera_info.dart';
export 'src/models/rr_interval.dart';
export 'src/models/signal_quality.dart';
export 'src/models/measurement_state.dart';
export 'src/models/finger_presence.dart';
export 'src/models/camera_ppg_error.dart';

// `[debug]` extras (spec note 19): present in the public API so the example's
// live-tuning playground can construct them for `CameraPpgSession`'s optional
// `policy`/`acceptance` constructor params, but NOT part of the frozen
// consumer contract — `mind_mobile` always omits them and relies on the
// kit's internal defaults.
export 'src/processing/rr_acceptance.dart' show RrAcceptance;
export 'src/processing/session_policy.dart' show SessionPolicy;

class CameraPpgKit {
  Future<String?> getPlatformVersion() {
    return CameraPpgKitPlatform.instance.getPlatformVersion();
  }
}
