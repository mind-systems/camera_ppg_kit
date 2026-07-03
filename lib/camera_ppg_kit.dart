
import 'camera_ppg_kit_platform_interface.dart';

// Frozen consumer surface (spec note 19/30): the CameraPpgSession
// streams/state machine, the camera-coverage UX methods (availableCameras,
// useCamera, buildPreview, resolvedCamera/resolvedCameraStream), and the
// exported model types below are the drop-in contract `mind_mobile` codes
// against. Adding to this surface after the freeze is a deliberate,
// consciously-made act — not an incidental one.
export 'src/api/camera_ppg_session.dart';
export 'src/models/camera_ppg_camera_info.dart';
export 'src/models/rr_interval.dart';
export 'src/models/signal_quality.dart';
export 'src/models/measurement_state.dart';
export 'src/models/finger_presence.dart';
export 'src/models/camera_ppg_error.dart';

// `[debug]` extras: present in the public API but NOT part of the frozen
// consumer contract above — `mind_mobile` always omits both. They exist so
// the example's live-tuning playground (kit-barrel-only imports) can
// construct tuned instances for `CameraPpgSession`'s optional ctor params:
// - `SessionPolicy? policy` — warm-up/duration/acceptance policy input.
// - `RrAcceptance? acceptance` — per-beat physiological acceptance-gate
//   input (spec note 19 names this input type `RrAcceptanceConfig`; the
//   real ctor param is `RrAcceptance? acceptance` — the type was renamed
//   after that note was written).
// The session also takes a third ctor param, `RrDehalving? dehalving`
// (spec note 30's adaptive de-halving stage), but `RrDehalving` is
// deliberately NOT exported here — its type never crosses the barrel, so
// the host cannot construct one; it is internal-default-only, not a public
// debug knob.
// `debugSignalStream` (declared on `CameraPpgSession`, re-exported above via
// the class itself) is this surface's one debug *output*: the red-channel
// waveform used by the example's signal-existence diagnostic.
// Neither the debug ctor inputs nor `debugSignalStream` is part of the
// drop-in contract.
export 'src/processing/rr_acceptance.dart' show RrAcceptance;
export 'src/processing/session_policy.dart' show SessionPolicy;

class CameraPpgKit {
  Future<String?> getPlatformVersion() {
    return CameraPpgKitPlatform.instance.getPlatformVersion();
  }
}
