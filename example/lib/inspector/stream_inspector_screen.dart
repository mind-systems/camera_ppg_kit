import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ppg/flutter_ppg.dart';

import '../auto_detect/camera_probe.dart';
import '../auto_detect/log.dart';
import '../common/finger_presence.dart';
import 'measurement_runner.dart';

/// Raw stream-inspector panel.
///
/// Runs a continuous [MeasurementRunner] on the supplied [camera] and renders
/// every [PPGSignal] field verbatim — no acceptance policy, no session
/// lifecycle. Purpose: answer "does a usable signal exist and what FPS does
/// the frame path sustain?" before committing to the full kit implementation.
///
/// Rebuild rate is intentionally slow (~3 Hz via [Timer.periodic]) so that
/// frequent widget rebuilds do not starve the camera frame stream and corrupt
/// the very FPS number being measured. The signal listener updates [_latest]
/// directly without calling [setState]; the timer tick triggers the repaint.
class StreamInspectorScreen extends StatefulWidget {
  const StreamInspectorScreen({super.key, required this.camera});

  /// The camera locked by the auto-detect probe. The inspector owns it for
  /// its entire lifetime and releases it in [dispose].
  final RearCamera camera;

  @override
  State<StreamInspectorScreen> createState() => _StreamInspectorScreenState();
}

class _StreamInspectorScreenState extends State<StreamInspectorScreen> {
  final MeasurementRunner _runner = MeasurementRunner();

  // Latest signal — written by the stream listener WITHOUT setState.
  // The periodic timer reads it and triggers a single coarse repaint.
  PPGSignal? _latest;

  // Running SQI tally — incremented cheaply in the stream listener.
  int _sqiPoor = 0;
  int _sqiFair = 0;
  int _sqiGood = 0;

  // Elapsed time — updated in the timer tick.
  final Stopwatch _elapsed = Stopwatch();

  StreamSubscription<PPGSignal>? _sub;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    ppgLog('Inspector opened on ${widget.camera.name}');
    _startRunner();
  }

  Future<void> _startRunner() async {
    await _runner.start(widget.camera);

    _elapsed.start();

    // Update _latest and the SQI tally WITHOUT setState — the timer drives
    // all repaints at a controlled ~3 Hz rate so the UI never starves frames.
    _sub = _runner.signals.listen((signal) {
      _latest = signal;
      switch (signal.quality) {
        case SignalQuality.poor:
          _sqiPoor++;
        case SignalQuality.fair:
          _sqiFair++;
        case SignalQuality.good:
          _sqiGood++;
      }
    });

    // Coarse repaint timer — 300 ms ≈ 3 Hz.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ppgLog('Inspector closing (back) — tearing down runner');
    _uiTimer?.cancel();
    _sub?.cancel();
    _runner.stop();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signal = _latest;
    final sustainedFps = _runner.sustainedFps;
    final elapsed = _elapsed.elapsed;
    final totalSqi = _sqiPoor + _sqiFair + _sqiGood;

    return Scaffold(
      appBar: AppBar(
        title: Text('Inspector — ${widget.camera.name}'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _elapsedRow(elapsed),
              const SizedBox(height: 12),
              _sqiTally(totalSqi),
              const SizedBox(height: 16),
              if (signal == null)
                const Text(
                  'Waiting for signal…',
                  style: TextStyle(fontFamily: 'monospace', color: Colors.grey),
                )
              else
                _signalPanel(signal, sustainedFps),
            ],
          ),
        ),
      ),
    );
  }

  // ── sub-widgets ─────────────────────────────────────────────────────────────

  Widget _elapsedRow(Duration elapsed) {
    final s = elapsed.inSeconds;
    final label =
        '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.timer_outlined, size: 18),
        const SizedBox(width: 6),
        Text('Elapsed: $label',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        const SizedBox(width: 12),
        Expanded(
          child: Text('(hold ~60 s for SQI distribution)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  Widget _sqiTally(int total) {
    String pct(int n) =>
        total == 0 ? '—' : '${(n / total * 100).toStringAsFixed(0)}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SQI distribution',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            _mono(
              'poor  $_sqiPoor  (${pct(_sqiPoor)})\n'
              'fair  $_sqiFair  (${pct(_sqiFair)})\n'
              'good  $_sqiGood  (${pct(_sqiGood)})\n'
              'total $total frames',
            ),
          ],
        ),
      ),
    );
  }

  Widget _signalPanel(PPGSignal s, double sustainedFps) {
    // Derived values for display.
    final lastRrMs = s.rrIntervals.isNotEmpty ? s.rrIntervals.last : null;
    final derivedBpm =
        lastRrMs != null && lastRrMs > 0 ? 60000 / lastRrMs : null;
    final fingerOk = isFingerPresent(s.rawIntensity);

    final qualityColor = switch (s.quality) {
      SignalQuality.good => Colors.green,
      SignalQuality.fair => Colors.orange,
      SignalQuality.poor => Colors.red,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── heart-rate section ───────────────────────────────────────────────
        _section('Heart rate', [
          _row('RR intervals (ms)',
              s.rrIntervals.isEmpty
                  ? '—'
                  : s.rrIntervals.map((v) => v.toStringAsFixed(0)).join(', ')),
          _row('Derived BPM',
              derivedBpm != null ? derivedBpm.toStringAsFixed(1) : '—'),
        ]),

        // ── quality section ──────────────────────────────────────────────────
        _section('Signal quality', [
          _rowColored('Quality (SQI)', s.quality.name.toUpperCase(),
              qualityColor),
          _row('SNR (dB)', s.snr.toStringAsFixed(2)),
          _row('Finger present', fingerOk ? 'YES' : 'no'),
        ]),

        // ── FPS section ──────────────────────────────────────────────────────
        _section('Frame rate', [
          _row('Sustained FPS (harness)', sustainedFps.toStringAsFixed(1)),
          _row('flutter_ppg frameRate', s.frameRate.toStringAsFixed(1)),
          _row('FPS stable', s.isFPSStable ? 'yes' : 'NO'),
        ]),

        // ── diagnostics section ──────────────────────────────────────────────
        _section('Diagnostics', [
          _row('Drift rate (int/s)', s.driftRate.toStringAsFixed(3)),
          _row('SDRR (ms)', s.sdrr.toStringAsFixed(2)),
          _row('SDRR acceptable', s.isSDRRAcceptable ? 'yes' : 'NO'),
          _row('Rejection ratio', s.rejectionRatio.toStringAsFixed(3)),
          _row('Rejected intervals', '${s.rejectedIntervalCount}'),
          _row('Raw intensity', s.rawIntensity.toStringAsFixed(2)),
          _row('Filtered intensity', s.filteredIntensity.toStringAsFixed(4)),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _rowColored(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _mono(String text) => Text(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      );
}
