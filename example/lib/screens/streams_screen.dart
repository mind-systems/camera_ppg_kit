import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';
// `flutter_riverpod` exports its own `AsyncError`, colliding with the widget
// kit's `AsyncError` (async_states.dart) — hide riverpod's so the kit's wins.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;

import '../providers/stream_providers.dart';
import '../services/source_lifecycle.dart';
import '../widgets/widgets.dart';

/// Streams screen — dogfoods the kit's **public barrel only** (spec note
/// 14).
///
/// Imports only `package:camera_ppg_kit/camera_ppg_kit.dart` — no
/// `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` type
/// appears here. Subscriptions live in the Riverpod providers; this widget
/// reads them with `ref.watch`/`ref.listen` and never opens a
/// `StreamBuilder` or a per-widget `.listen()` of its own — a rebuild must
/// never re-subscribe.
///
/// Pure display consumer (spec note 22 / Task 4): no lifecycle, no camera,
/// no `startMeasurement`/`stopMeasurement` — those moved to the Source
/// screen, the shell's sole owner of the source lifecycle. Stays a
/// `ConsumerStatefulWidget` solely for the `_rrHistory` UI-only rolling list.
class StreamsScreen extends ConsumerStatefulWidget {
  const StreamsScreen({super.key});

  @override
  ConsumerState<StreamsScreen> createState() => _StreamsScreenState();
}

class _StreamsScreenState extends ConsumerState<StreamsScreen> {
  // ── RR rolling list (display-only, cleared on every new warm-up) ───────
  final List<RrInterval> _rrHistory = [];

  @override
  Widget build(BuildContext context) {
    // Providers, not raw streams — a rebuild here re-reads provider state,
    // it never re-subscribes (the subscription lives in the provider).
    ref.listen<AsyncValue<RrInterval>>(rrProvider, (previous, next) {
      next.whenData((rr) {
        setState(() {
          _rrHistory.insert(0, rr);
          if (_rrHistory.length > 12) _rrHistory.removeLast();
        });
      });
    });
    ref.listen<AsyncValue<MeasurementState>>(stateProvider, (previous, next) {
      // `warmup` is entered exactly once per measurement, right after a
      // sensor locks — clear the rolling list here so it never shows beats
      // from a previous measurement.
      next.whenData((s) {
        if (s == MeasurementState.warmup) {
          setState(() => _rrHistory.clear());
        }
      });
    });

    final lifecycle = ref.watch(lifecycleProvider).value ?? SourceLifecycle.idle;
    final (label, color) = _stateLabelColor(lifecycle);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StateBanner(label, color),
          const SizedBox(height: 16),
          _bpmCard(),
          const SizedBox(height: 16),
          _rrCard(),
          const SizedBox(height: 16),
          _signalCard(),
        ],
      ),
    );
  }

  /// Maps [SourceLifecycle] onto its banner label + semantic color — own
  /// copy, deliberately not factored into a shared widget (Scope notes).
  /// During teardown this shows **Stopping…** rather than a frozen
  /// "Measuring" (spec note 33). No `done`/"Complete" arm is reintroduced
  /// (note 23) — the terminal path is always `stopping -> idle`.
  ///
  /// `poorSignal → fairColor` (orange) is intentional: `poorColor` (red) is
  /// reserved for error states, so a later edit should not "correct" this to
  /// `poorColor`.
  (String, Color) _stateLabelColor(SourceLifecycle lifecycle) => switch (lifecycle) {
        SourceLifecycle.idle => ('Idle', idleColor),
        SourceLifecycle.starting => ('Starting…', pendingColor),
        SourceLifecycle.warmup => ('Hold still… warming up', pendingColor),
        SourceLifecycle.measuring => ('Measuring', goodColor),
        SourceLifecycle.poorSignal => ('Poor signal — check finger placement', fairColor),
        SourceLifecycle.stopping => ('Stopping…', pendingColor),
      };

  /// Headline metric — the biggest, most prominent number on the screen.
  Widget _bpmCard() {
    final bpm = ref.watch(bpmProvider);
    return SectionCard(
      title: 'BPM',
      child: Center(
        child: Column(
          children: [
            Text(
              bpm?.toString() ?? '—',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 56, fontWeight: FontWeight.bold),
            ),
            const Text('derived, display-only', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  /// Latest RR interval plus the rolling per-beat history. Artifacts are
  /// flagged (color, an asterisk) rather than filtered out — a developer
  /// wants to see rejected beats (spec note 14).
  ///
  /// `rrProvider` is a `StreamProvider` that sits in the `loading` state
  /// (not a null-data state) until its first emit, so the latest-interval
  /// line is gated on the `AsyncValue` itself, mirroring `_signalCard` in
  /// `source_screen.dart`.
  Widget _rrCard() {
    final rrAsync = ref.watch(rrProvider);

    return SectionCard(
      title: 'Live RR',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rrAsync.when(
            data: (rr) => Text(
              'Latest: ${rr.intervalMs} ms${rr.isArtifact ? ' (artifact)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            loading: () => const AsyncEmpty('waiting for signal…'),
            error: (error, _) => AsyncError(error),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final rr in _rrHistory)
                StatusChip('${rr.intervalMs}${rr.isArtifact ? '*' : ''}', rr.isArtifact ? poorColor : goodColor),
            ],
          ),
        ],
      ),
    );
  }

  /// Own copy of the status display (Scope notes) — the Source screen keeps
  /// an identical copy; deliberately not factored into a shared widget.
  ///
  /// `qualityProvider` is a `StreamProvider` that sits in the `loading`
  /// state (not a null-data state) until its first emit, so the SQI chip is
  /// gated on the `AsyncValue` itself: `loading` renders `AsyncEmpty`
  /// ("waiting for signal…"), `data` renders the `StatusChip`, `error`
  /// renders `AsyncError`. Finger-presence has no live-source ambiguity in
  /// practice worth a spinner, so it stays a plain `LabelRow` reusing the
  /// existing `null → 'unknown'` fallback.
  Widget _signalCard() {
    final qualityAsync = ref.watch(qualityProvider);
    final presence = ref.watch(fingerPresenceProvider).value;

    final presenceLabel = switch (presence) {
      FingerPresence.present => 'finger present',
      FingerPresence.absent => 'no finger',
      FingerPresence.overBright => 'over-bright (not covering flash)',
      null => 'unknown',
    };

    return SectionCard(
      title: 'Signal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          qualityAsync.when(
            data: (quality) => StatusChip('SQI: ${quality.name}', qualityColor(quality)),
            loading: () => const AsyncEmpty('waiting for signal…'),
            error: (error, _) => AsyncError(error),
          ),
          const SizedBox(height: 8),
          LabelRow('Finger', presenceLabel),
        ],
      ),
    );
  }
}
