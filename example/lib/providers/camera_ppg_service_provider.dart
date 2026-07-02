import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/camera_ppg_service.dart';

/// Owns the [CameraPpgService] singleton for the example app's Kit-API tab.
///
/// This is what releases the camera + torch on scope teardown: [ref.onDispose]
/// calls [CameraPpgService.dispose], mirroring `neiry_kit`'s
/// `neiryServiceProvider`.
final cameraPpgServiceProvider = Provider<CameraPpgService>((ref) {
  final s = CameraPpgService();
  ref.onDispose(s.dispose);
  return s;
});
