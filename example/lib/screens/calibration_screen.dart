import 'dart:async';

import 'package:flutter/material.dart';
// `flutter_riverpod` exports its own `AsyncError`, colliding with the widget
// kit's `AsyncError` (async_states.dart) — hide riverpod's so the kit's wins.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;

import '../auto_detect/log.dart';
import '../calibration/calibration_recorder.dart';
import '../providers/camera_ppg_service_provider.dart';
import '../providers/session_config_provider.dart';
import '../providers/stream_providers.dart';
import '../services/source_lifecycle.dart';
import '../widgets/widgets.dart';

/// Calibration branch — a **pure consumer** of the already-flowing RR stream
/// (spec note 21). The source is owned by the [CameraPpgService] singleton
/// and started/stopped exclusively from the Source screen (note 22); this
/// screen never calls `startMeasurement`/`stopMeasurement`, never opens a
/// `CameraController`/torch, and never gates on [stateProvider] — only on
/// its own local `_recording` flag.
///
/// "Start recording" arms a screen-owned `1:00 -> 0:00` countdown bounding a
/// [CalibrationRecorder] window over the live source. The 60 s window is
/// data to teach the algorithm, not a session limit — the kit's measurement
/// session stays open-ended regardless of this screen's countdown.
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  final CalibrationRecorder _recorder = CalibrationRecorder();
  final TextEditingController _beatsController = TextEditingController();

  Timer? _finishTimer;
  Timer? _tickTimer;
  int _remainingSeconds = 60;
  int _windowSeconds = 0;
  bool _recording = false;
  bool _recorded = false;
  String? _savedPath;
  bool _blockedByNotMeasuring = false;

  void _startRecording() {
    ppgTap('calib_record_start');
    final service = ref.read(cameraPpgServiceProvider);
    if (!service.isMeasuring) {
      setState(() => _blockedByNotMeasuring = true);
      return;
    }
    setState(() => _blockedByNotMeasuring = false);

    final config = ref.read(sessionConfigProvider);
    _recorder.start(service, config.acceptance, config.policy);

    setState(() {
      _recording = true;
      _recorded = false;
      _remainingSeconds = 60;
      _savedPath = null;
    });

    _finishTimer = Timer(const Duration(seconds: 60), _finish);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (_remainingSeconds > 0) _remainingSeconds--;
      });
    });
  }

  /// Idempotent — shared by the 60 s auto-timer and the manual Stop button,
  /// so whichever fires first finalizes the run exactly once.
  void _finish() {
    if (!_recording) return;
    _finishTimer?.cancel();
    _tickTimer?.cancel();
    _finishTimer = null;
    _tickTimer = null;
    _windowSeconds = 60 - _remainingSeconds;
    _recorder.stop();
    setState(() {
      _recording = false;
      _recorded = true;
    });
    ppgLog('calib recording complete');
  }

  void _stopManually() {
    ppgTap('calib_record_stop');
    _finish();
  }

  Future<void> _save() async {
    ppgTap('calib_save');
    final beats = int.tryParse(_beatsController.text);
    final path = await _recorder.save(
      countedBeats: beats,
      countWindowSeconds: _windowSeconds,
    );
    if (!mounted) return;
    setState(() => _savedPath = path);
    ppgLog(path);
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _tickTimer?.cancel();
    _beatsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stateBanner(),
          const SizedBox(height: 16),
          _countdownCard(),
          const SizedBox(height: 16),
          _recordButtonsRow(),
          if (_blockedByNotMeasuring) ...[
            const SizedBox(height: 12),
            _guidanceBanner(),
          ],
          const SizedBox(height: 16),
          _bpmSection(),
          const SizedBox(height: 16),
          _signalCard(),
          const SizedBox(height: 16),
          _saveCard(),
        ],
      ),
    );
  }

  /// Wrapped in its own [Consumer] for the same isolation reason as
  /// [_bpmSection]: `lifecycleProvider` can emit as often as the underlying
  /// kit state does, so watching it in a leaf keeps that rebuild off the
  /// countdown/buttons (note 21).
  Widget _stateBanner() {
    return Consumer(
      builder: (context, ref, _) {
        final lifecycle = ref.watch(lifecycleProvider).value ?? SourceLifecycle.idle;
        final (label, color) = _stateLabelColor(lifecycle);
        return StateBanner(label, color);
      },
    );
  }

  /// Maps [SourceLifecycle] onto its banner label + semantic color — copied
  /// from `streams_screen.dart:_stateLabelColor` (own copy, deliberately not
  /// factored into a shared widget, Scope notes). During teardown this shows
  /// **Stopping…** rather than a frozen "Measuring" (spec note 33). No
  /// `done`/"Complete" arm is reintroduced (note 23) — the terminal path is
  /// always `stopping -> idle`.
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

  Widget _countdownCard() {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(1, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return SectionCard(
      title: 'Countdown',
      child: Center(
        child: Text(
          '$m:$s',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 64, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _recordButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _recording ? null : _startRecording,
            child: const Text('Start recording'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: _recording ? _stopManually : null,
            child: const Text('Stop'),
          ),
        ),
      ],
    );
  }

  Widget _guidanceBanner() {
    return const StateBanner('Start measurement on the Source screen first', fairColor);
  }

  /// Wrapped in its own [Consumer] rather than reading `ref.watch` straight
  /// from the enclosing state's `build()` (review finding 1): `bpmProvider`
  /// emits at frame cadence (~24–30 FPS, `camera_ppg_session.dart`), and a
  /// `ref.watch` sitting in a helper method invoked from `build()` registers
  /// the *whole* screen element as its dependent — rebuilding the countdown
  /// and buttons alongside it. Isolating the watch in a `Consumer` confines
  /// the frame-rate rebuild to this leaf, leaving `_countdownCard()` driven
  /// only by the 1 Hz `_tickTimer`, per note 21.
  Widget _bpmSection() {
    return Consumer(
      builder: (context, ref, _) {
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
      },
    );
  }

  /// Own copy of the status display (Scope notes) — Source/Streams keep
  /// identical copies; deliberately not factored into a shared widget.
  ///
  /// Wrapped in its own [Consumer] for the same reason as [_bpmSection]:
  /// `qualityProvider` also emits every processed frame, so isolating the
  /// watch here keeps that frame-rate rebuild off the countdown/buttons.
  Widget _signalCard() {
    return Consumer(
      builder: (context, ref, _) {
        final qualityAsync = ref.watch(qualityProvider);
        return SectionCard(
          title: 'Signal',
          child: qualityAsync.when(
            data: (quality) => StatusChip('SQI: ${quality.name}', qualityColor(quality)),
            loading: () => const AsyncEmpty('waiting for signal…'),
            error: (error, _) => AsyncError(error),
          ),
        );
      },
    );
  }

  Widget _saveCard() {
    return SectionCard(
      title: 'Save',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _beatsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Counted beats (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _recorded ? _save : null,
            child: const Text('Save'),
          ),
          if (_savedPath != null) ...[
            const SizedBox(height: 12),
            SelectableText(_savedPath!),
          ],
        ],
      ),
    );
  }
}
