import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_ppg_service_provider.dart';

/// Every RR interval from the current measurement, artifacts included —
/// the Kit-API tab shows [RrInterval.isArtifact] rather than filtering it
/// out (a developer wants to see rejected beats).
final rrProvider = StreamProvider<RrInterval>((ref) {
  return ref.watch(cameraPpgServiceProvider).rrStream;
});

/// Coarse signal-quality band, driving the SQI chip.
final qualityProvider = StreamProvider<SignalQuality>((ref) {
  return ref.watch(cameraPpgServiceProvider).qualityStream;
});

/// Measurement lifecycle state — render this directly, never reimplement the
/// warm-up/measuring/poorSignal state machine (that is the kit's, spec
/// note 09).
final stateProvider = StreamProvider<MeasurementState>((ref) {
  return ref.watch(cameraPpgServiceProvider).stateStream;
});

/// Finger-presence classification, driving "press your finger" guidance.
final fingerPresenceProvider = StreamProvider<FingerPresence>((ref) {
  return ref.watch(cameraPpgServiceProvider).fingerPresenceStream;
});

/// Display-only derived BPM — never pushed into the kit (BPM/HRV are the
/// consumer's concern, spec note 07).
///
/// The kit emits artifact beats on the same [rrProvider] stream (they are
/// shown, not filtered, per spec note 14), so the *latest* [RrInterval] is
/// frequently `isArtifact == true`. A naive `60000 ~/ rrProvider.value.intervalMs`
/// would either read BPM off an artifact beat or go stale whenever the
/// newest beat is one. This [Notifier] instead ignores artifact beats and
/// retains the BPM derived from the last accepted beat across intervening
/// artifact ticks (through [MeasurementState.measuring] and
/// [MeasurementState.poorSignal] alike), resetting to `null` whenever the
/// state isn't actively trusting RR — `idle` (no live signal to display) and
/// `warmup` (a new measurement has begun; discard the previous one's BPM
/// before its first RR arrives) — per review finding 3.
class BpmNotifier extends Notifier<int?> {
  @override
  int? build() {
    final service = ref.watch(cameraPpgServiceProvider);

    // `cameraPpgServiceProvider` is a plain (non-rebuilding) `Provider`, so
    // `build()` runs exactly once per [BpmNotifier] lifetime — no need to
    // cancel a prior subscription before listening here (review finding 4).
    final rrSub = service.rrStream.listen((rr) {
      if (rr.isArtifact) return;
      if (rr.intervalMs <= 0) return;
      state = 60000 ~/ rr.intervalMs;
    });
    final stateSub = service.stateStream.listen((s) {
      switch (s) {
        case MeasurementState.idle:
        case MeasurementState.warmup:
          state = null;
        case MeasurementState.measuring:
        case MeasurementState.poorSignal:
          break;
      }
    });

    ref.onDispose(() {
      rrSub.cancel();
      stateSub.cancel();
    });

    return null;
  }
}

final bpmProvider = NotifierProvider<BpmNotifier, int?>(BpmNotifier.new);
