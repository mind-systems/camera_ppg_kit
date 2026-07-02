import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/stream_providers.dart';

/// Kit-API branch — dogfoods the kit's **public barrel only** (spec note
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
class KitApiTab extends ConsumerStatefulWidget {
  const KitApiTab({super.key});

  @override
  ConsumerState<KitApiTab> createState() => _KitApiTabState();
}

class _KitApiTabState extends ConsumerState<KitApiTab> {
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

    final stateAsync = ref.watch(stateProvider);
    final state = stateAsync.value ?? MeasurementState.idle;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stateBanner(state),
          const SizedBox(height: 16),
          _qualityAndPresenceRow(),
          const SizedBox(height: 16),
          _bpmSection(),
          const SizedBox(height: 16),
          _rrSection(),
        ],
      ),
    );
  }

  Widget _stateBanner(MeasurementState state) {
    final (label, color) = switch (state) {
      MeasurementState.idle => ('Idle', Colors.grey),
      MeasurementState.warmup => ('Hold still… warming up', Colors.blue),
      MeasurementState.measuring => ('Measuring', Colors.green),
      MeasurementState.poorSignal => ('Poor signal — check finger placement', Colors.orange),
      MeasurementState.done => ('Complete', Colors.indigo),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Own copy of the status display (Scope notes) — the Source screen keeps
  /// an identical copy; deliberately not factored into a shared widget.
  Widget _qualityAndPresenceRow() {
    final quality = ref.watch(qualityProvider).value;
    final presence = ref.watch(fingerPresenceProvider).value;

    final qualityColor = switch (quality) {
      SignalQuality.good => Colors.green,
      SignalQuality.fair => Colors.orange,
      SignalQuality.poor => Colors.red,
      null => Colors.grey,
    };
    final presenceLabel = switch (presence) {
      FingerPresence.present => 'finger present',
      FingerPresence.absent => 'no finger',
      FingerPresence.overBright => 'over-bright (not covering flash)',
      null => 'unknown',
    };

    return Row(
      children: [
        Chip(
          label: Text('SQI: ${quality?.name ?? '—'}'),
          backgroundColor: qualityColor.withValues(alpha: 0.15),
          labelStyle: TextStyle(color: qualityColor, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(presenceLabel, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _bpmSection() {
    final bpm = ref.watch(bpmProvider);
    return Center(
      child: Column(
        children: [
          Text(
            bpm?.toString() ?? '—',
            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
          ),
          const Text('BPM (derived, display-only)', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _rrSection() {
    final latest = ref.watch(rrProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latest RR: ${latest != null ? '${latest.intervalMs} ms${latest.isArtifact ? ' (artifact)' : ''}' : '—'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final rr in _rrHistory)
              Chip(
                label: Text('${rr.intervalMs}${rr.isArtifact ? '*' : ''}'),
                backgroundColor: rr.isArtifact ? Colors.red.shade50 : Colors.green.shade50,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: rr.isArtifact ? Colors.red : Colors.green.shade800,
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}
