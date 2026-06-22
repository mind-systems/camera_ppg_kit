import 'package:flutter/material.dart';

import '../inspector/stream_inspector_screen.dart';
import 'auto_detect_result.dart';
import 'camera_probe.dart';
import 'coverage_detector.dart';
import 'log.dart';

/// Developer-facing panel that exercises the signal-based camera auto-detect
/// spike: enumerates rear cameras, runs the coverage round-trip, and shows
/// per-camera probe results.
///
/// State is plain [StatefulWidget] + [setState]; Riverpod / go_router are
/// deferred to Phase 9. Rebuilds are coarse — only on phase changes and
/// per-camera summaries, never per-frame.
class AutoDetectScreen extends StatefulWidget {
  const AutoDetectScreen({super.key});

  @override
  State<AutoDetectScreen> createState() => _AutoDetectScreenState();
}

enum _Phase { idle, probing, done }

class _AutoDetectScreenState extends State<AutoDetectScreen> {
  _Phase _phase = _Phase.idle;

  List<RearCamera> _rearCameras = [];
  bool _enumerating = false;

  CoverageOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _enumerate();
  }

  Future<void> _enumerate() async {
    ppgLog('Enumerating rear cameras…');
    setState(() => _enumerating = true);
    try {
      final cams = await enumerateRearCameras();
      ppgLog('Enumerated ${cams.length} rear camera(s): '
          '${cams.map((c) => "#${c.index} ${c.name}").join(", ")}');
      if (!mounted) return;
      setState(() {
        _rearCameras = cams;
        _enumerating = false;
      });
    } catch (e, st) {
      // availableCameras() throws on simulators/emulators (no camera plugin)
      // and on denied access — leave _rearCameras empty and clear the spinner.
      ppgLog('Enumerate failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _enumerating = false);
    }
  }

  Future<void> _start() async {
    if (_rearCameras.isEmpty) {
      ppgLog('Start ignored — no rear cameras enumerated');
      return;
    }
    ppgLog('Coverage round-trip starting over ${_rearCameras.length} camera(s)');
    setState(() {
      _phase = _Phase.probing;
      _outcome = null;
    });

    // Run the sequential round-trip.
    // Per-camera progress is shown by watching _probingIndex; we update it
    // after each camera is done by listening to the outcome records list
    // growing — but coverage_detector is a single awaited Future, so we
    // can only show overall "probing…" during the run. A future milestone
    // can expose a stream for finer progress.
    final outcome = await detectCoveredCamera(
      _rearCameras,
      warmUp: const Duration(milliseconds: 400),
      dwell: const Duration(milliseconds: 700),
    );

    ppgLog(outcome.isSuccess
        ? 'Round-trip done → LOCKED #${outcome.lockedCamera!.index} '
            '${outcome.lockedCamera!.name}'
        : 'Round-trip done → FAILED ${outcome.error!.name}');

    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera PPG — Auto-detect spike')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _guidanceCard(),
              const SizedBox(height: 16),
              _cameraListSection(),
              const SizedBox(height: 16),
              _startButton(),
              const SizedBox(height: 16),
              if (_phase != _Phase.idle) _resultSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guidanceCard() {
    return Card(
      color: Colors.blue.shade50,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Place a finger over a rear lens AND the flash, then press Start.\n'
          'Keep the finger still — the probe runs ~1 second per camera.',
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _cameraListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Rear cameras',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            if (_enumerating)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: _phase == _Phase.probing
                    ? null
                    : () {
                        ppgTap('Re-probe');
                        _enumerate();
                      },
                child: const Text('Re-probe'),
              ),
          ],
        ),
        if (!_enumerating && _rearCameras.isEmpty)
          const Text('No rear cameras found.',
              style: TextStyle(color: Colors.red)),
        for (final cam in _rearCameras)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '  #${cam.index}  ${cam.name}  '
              'orient: ${cam.sensorOrientation}°  '
              'type: ${cam.lensType.name}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _startButton() {
    final busy = _phase == _Phase.probing;
    return ElevatedButton(
      onPressed: busy || _rearCameras.isEmpty
          ? null
          : () {
              ppgTap('Start');
              _start();
            },
      child: busy
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 8),
                Text('Probing cameras…'),
              ],
            )
          : const Text('Start'),
    );
  }

  Widget _resultSection() {
    final outcome = _outcome;

    if (_phase == _Phase.probing) {
      return const Center(child: Text('Running coverage round-trip…'));
    }

    if (outcome == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── overall verdict ───────────────────────────────────────────────
        if (outcome.isSuccess)
          _successBanner(outcome.lockedCamera!)
        else
          _failureBanner(outcome.error!),
        const SizedBox(height: 12),
        // ── per-camera records ────────────────────────────────────────────
        const Text('Per-camera probe records:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        for (final rec in outcome.records)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  rec.covered ? Icons.check_circle : Icons.cancel,
                  color: rec.covered ? Colors.green : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '#${rec.camera.index} ${rec.camera.name}  '
                    'frames: ${rec.framesSeen}  '
                    'covered: ${rec.coveredFrames}  '
                    '(${(rec.coveredFraction * 100).toStringAsFixed(0)}%)',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // ── retry affordance on failure ───────────────────────────────────
        if (!outcome.isSuccess)
          OutlinedButton(
            onPressed: () {
              ppgTap('Retry');
              _start();
            },
            child: const Text('Retry'),
          ),
      ],
    );
  }

  Widget _successBanner(RearCamera cam) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✓ Camera locked',
              style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            '#${cam.index}  ${cam.name}\n'
            'lensType: ${cam.lensType.name}  '
            'orientation: ${cam.sensorOrientation}°',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 12),
          // The auto-detect round-trip has fully torn down the camera before
          // reaching this point, so the inspector can safely open it fresh.
          ElevatedButton.icon(
            onPressed: () {
              ppgTap('Open stream inspector → #${cam.index} ${cam.name}');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StreamInspectorScreen(camera: cam),
                ),
              );
            },
            icon: const Icon(Icons.stream),
            label: const Text('Open stream inspector'),
          ),
        ],
      ),
    );
  }

  Widget _failureBanner(AutoDetectError error) {
    final message = switch (error) {
      AutoDetectError.noCoveredCamera =>
        'No covered camera detected.\n'
            'Place your finger firmly over a rear lens AND the flash, then retry.',
      AutoDetectError.permissionDenied =>
        'Camera permission denied.\n'
            'Grant camera access in Settings and try again.',
      AutoDetectError.cameraError =>
        'A camera error occurred.\n'
            'Check device logs for details.',
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      padding: const EdgeInsets.all(12),
      child: Text(message,
          style: const TextStyle(color: Colors.deepOrange, fontSize: 14)),
    );
  }
}
