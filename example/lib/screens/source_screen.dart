import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';
// `flutter_riverpod` exports its own `AsyncError`, colliding with the widget
// kit's `AsyncError` (async_states.dart) — hide riverpod's so the kit's wins.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;
import 'package:permission_handler/permission_handler.dart';

import '../auto_detect/log.dart';
import '../providers/camera_ppg_service_provider.dart';
import '../providers/session_config_provider.dart';
import '../providers/stream_providers.dart';
import '../services/source_lifecycle.dart';
import '../widgets/widgets.dart';

/// Source branch — the **sole** screen that issues
/// `service.startMeasurement()` / `stopMeasurement()`, mirroring neiry's
/// `device_screen` (spec note 22). Kit-API and Raw are pure consumers; only
/// this screen commands the [CameraPpgService] singleton, which still owns
/// the session across navigation (the shell keeps every branch mounted).
///
/// Carries the camera-permission flow, camera override, and the `[debug]`
/// tuning panel — all relocated here from `streams_screen.dart` (Task 4 strips
/// them there). The tuning panel seeds from and writes to
/// [sessionConfigProvider] so the config it starts with is always the same
/// one the future calibration screen will read (note 21).
class SourceScreen extends ConsumerStatefulWidget {
  const SourceScreen({super.key});

  @override
  ConsumerState<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends ConsumerState<SourceScreen> {
  // ── Camera override ───────────────────────────────────────────────────
  List<CameraPpgCameraInfo> _cameras = [];
  String? _selectedCameraId;
  bool _loadingCameras = false;

  // ── Start/stop outcome ────────────────────────────────────────────────
  CameraPpgError? _lastError;

  bool _debugExpanded = false;

  @override
  void initState() {
    super.initState();
    // Deferred rather than called directly: mounting this screen inside the
    // shell's `IndexedStack` can happen during the shell's own build/layout
    // pass, and `_loadCameras`'s synchronous pre-await `setState()` can trip
    // a "setState() called during build" assertion if it runs inline from
    // `initState` in that window. A post-frame callback runs it once the
    // current build/layout has finished instead (mirrors streams_screen).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCameras());
  }

  Future<void> _loadCameras() async {
    setState(() => _loadingCameras = true);
    final cameras = await ref.read(cameraPpgServiceProvider).availableCameras();
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      _loadingCameras = false;
      // Drop a selection the refreshed enumeration no longer contains —
      // otherwise DropdownButton asserts that its `value` matches exactly
      // one item.
      if (_selectedCameraId != null && !_cameras.any((c) => c.id == _selectedCameraId)) {
        _selectedCameraId = null;
      }
    });
  }

  void _selectCamera(String? id) {
    ppgTap('source_camera_override:${id ?? "auto"}');
    setState(() => _selectedCameraId = id);
  }

  /// Requests camera permission and reports whether `_start()` may proceed.
  ///
  /// Mirrors neiry's `_scan()` permission flow: granted → proceed; denied →
  /// surface a retryable error; permanently denied/restricted → deep-link to
  /// app settings and surface the permanently-denied error variant so the
  /// existing `_errorBanner` shows the settings guidance line. Never calls
  /// `startMeasurement()` itself — the caller decides what "proceed" means.
  Future<bool> _checkAndRequestCameraPermission() async {
    ppgTap('source_permission_request');
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied || status.isRestricted) {
      ppgTap('source_permission_open_settings');
      await openAppSettings();
      if (!mounted) return false;
      setState(() {
        _lastError = CameraPpgError.permissionDenied(permanentlyDenied: true);
      });
      return false;
    }
    if (!mounted) return false;
    setState(() => _lastError = CameraPpgError.permissionDenied());
    return false;
  }

  Future<void> _start() async {
    ppgTap('source_start');
    if (!await _checkAndRequestCameraPermission()) return;
    if (!mounted) return;
    setState(() => _lastError = null);
    final service = ref.read(cameraPpgServiceProvider);
    final config = ref.read(sessionConfigProvider);
    final error = await service.startMeasurement(
      cameraId: _selectedCameraId,
      policy: config.policy,
      acceptance: config.acceptance,
    );
    if (!mounted) return;
    setState(() => _lastError = error);
  }

  Future<void> _stop() async {
    ppgTap('source_stop');
    await ref.read(cameraPpgServiceProvider).stopMeasurement();
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = ref.watch(lifecycleProvider).value ?? SourceLifecycle.idle;
    final (label, color) = _stateLabelColor(lifecycle);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StateBanner(label, color),
          const SizedBox(height: 12),
          if (_lastError != null) ...[
            _errorBanner(_lastError!),
            const SizedBox(height: 12),
          ],
          _controlCard(lifecycle),
          const SizedBox(height: 16),
          _signalCard(lifecycle),
          const SizedBox(height: 16),
          _cameraOverrideCard(lifecycle),
          const SizedBox(height: 16),
          _debugPanel(),
        ],
      ),
    );
  }

  /// Maps [SourceLifecycle] onto its banner label + semantic color. Only the
  /// six lifecycle values — no `done`/"Complete" arm is reintroduced (note
  /// 23); the terminal path is always `stopping -> idle`.
  ///
  /// `poorSignal → fairColor` (orange) is intentional: `poorColor` (red) is
  /// reserved for the error banner, so a later edit should not "correct"
  /// this to `poorColor`.
  (String, Color) _stateLabelColor(SourceLifecycle lifecycle) => switch (lifecycle) {
        SourceLifecycle.idle => ('Idle', idleColor),
        SourceLifecycle.starting => ('Starting…', pendingColor),
        SourceLifecycle.warmup => ('Hold still… warming up', pendingColor),
        SourceLifecycle.measuring => ('Measuring', goodColor),
        SourceLifecycle.poorSignal => ('Poor signal — check finger placement', fairColor),
        SourceLifecycle.stopping => ('Stopping…', pendingColor),
      };

  Widget _errorBanner(CameraPpgError error) {
    final message = error.message != null ? ' — ${error.message}' : '';
    final guidance = error.permanentlyDenied
        ? '\nPermission permanently denied — grant it in system settings.'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StateBanner('${error.type.name}$message$guidance', poorColor),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              ppgTap('source_retry');
              _start();
            },
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  /// Both buttons disabled + a small inline spinner during
  /// [SourceLifecycle.isTransitional] (`starting`/`stopping`) — a slow or
  /// hanging teardown reads as honest "Stopping…" progress instead of a
  /// frozen active state (spec note 33).
  Widget _controlCard(SourceLifecycle lifecycle) {
    final transitional = lifecycle.isTransitional;
    return SectionCard(
      title: 'Control',
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: lifecycle == SourceLifecycle.idle ? () => _start() : null,
              child: transitional
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Start'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: lifecycle.isActive ? _stop : null,
              child: transitional
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Stop'),
            ),
          ),
        ],
      ),
    );
  }

  /// Source status — its **own copy** of the status display, so the operator
  /// confirms the source is live before navigating to a consumer screen.
  /// Kit-API keeps an identical copy (Scope notes) — deliberately not
  /// factored into a shared widget.
  ///
  /// Top row is the SQI chip beside a small square live-camera preview (plan
  /// 27, folding in note 35's standalone preview card); `Finger` stays its
  /// own row below, unchanged.
  ///
  /// Both the SQI side and the preview square are gated on `lifecycle`, not
  /// on the last stream/session value: while `!lifecycle.isActive` (`idle`,
  /// `starting`, `stopping`) they always show "waiting for signal…" /
  /// placeholder, even if `qualityProvider` or the session still hold a
  /// stale last value from before Stop. Only while `lifecycle.isActive`
  /// (`warmup`/`measuring`/`poorSignal`) do they render the live values:
  ///
  /// - SQI: `qualityProvider` is a `StreamProvider` that sits in the
  ///   `loading` state (not a null-data state) until its first emit, so the
  ///   chip is gated on the `AsyncValue` itself: `loading` renders
  ///   `AsyncEmpty` ("waiting for signal…"), `data` renders the
  ///   `StatusChip`, `error` renders `AsyncError`.
  /// - Preview: `buildPreview()` is read fresh on every build — never cached
  ///   across a stop — so the placeholder → live-texture flip rides the same
  ///   `ref.watch(lifecycleProvider)` rebuild already driving the rest of
  ///   this screen (`starting -> warmup` is the first rebuild where the
  ///   session has a locked, initialized controller); it naturally reverts
  ///   to the placeholder once `stop()`/`dispose()` null out the session's
  ///   controller, and the `lifecycle` gate above forces that reversion the
  ///   instant Stop is pressed rather than waiting on the last emit.
  ///
  /// Finger-presence has no live-source ambiguity in practice worth a
  /// spinner, so it stays a plain `LabelRow` reusing the existing
  /// `null → 'unknown'` fallback, and is deliberately left ungated.
  Widget _signalCard(SourceLifecycle lifecycle) {
    final qualityAsync = ref.watch(qualityProvider);
    final presence = ref.watch(fingerPresenceProvider).value;
    final active = lifecycle.isActive;

    final presenceLabel = switch (presence) {
      FingerPresence.present => 'finger present',
      FingerPresence.absent => 'no finger',
      FingerPresence.overBright => 'over-bright (not covering flash)',
      null => 'unknown',
    };

    final preview = active ? ref.read(cameraPpgServiceProvider).session?.buildPreview() : null;

    return SectionCard(
      title: 'Signal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: !active
                    ? const AsyncEmpty('waiting for signal…')
                    : qualityAsync.when(
                        data: (quality) => StatusChip('SQI: ${quality.name}', qualityColor(quality)),
                        loading: () => const AsyncEmpty('waiting for signal…'),
                        error: (error, _) => AsyncError(error),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: preview ?? const AsyncEmpty('no preview'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabelRow('Finger', presenceLabel),
        ],
      ),
    );
  }

  /// Lets the developer pin a rear sensor via [CameraPpgSession.useCamera]
  /// (through the service), or leave it on auto-detect (the default).
  ///
  /// Camera choice is locked (dropdown/Refresh disabled) whenever
  /// `lifecycle != SourceLifecycle.idle` — during `starting`/active/`stopping`
  /// alike, not just while actively measuring (spec note 33).
  ///
  /// Also shows which sensor auto-detect (or the pin) actually locked, read
  /// fresh off the session's `resolvedCamera` (plan 26) — the text
  /// complement to `_signalCard()`'s live preview square, so camera selection
  /// is verifiable without reading pixels. Read directly rather than through
  /// a stream provider: this rides the same `ref.watch(lifecycleProvider)`
  /// rebuild `_signalCard()` already relies on, so no extra wiring is
  /// needed. The transient `'auto-detecting…'` text is gated on
  /// [SourceLifecycle.starting] specifically, not on "locked but
  /// unresolved" in general — `stopMeasurement()` nulls the service's
  /// session before awaiting `dispose()`, so `resolvedCamera` also reads
  /// `null` during `stopping`; without this gate that sub-second teardown
  /// window would misleadingly read "auto-detecting…" (review finding 1).
  Widget _cameraOverrideCard(SourceLifecycle lifecycle) {
    final locked = lifecycle != SourceLifecycle.idle;
    final resolved = ref.read(cameraPpgServiceProvider).session?.resolvedCamera;
    final resolvedLabel = resolved != null
        ? '${resolved.id} (${resolved.lensType})'
        : lifecycle == SourceLifecycle.starting
            ? 'auto-detecting…'
            : '—';
    return SectionCard(
      title: 'Camera override',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_loadingCameras)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: locked
                      ? null
                      : () {
                          ppgTap('source_refresh_cameras');
                          _loadCameras();
                        },
                  child: const Text('Refresh'),
                ),
            ],
          ),
          DropdownButton<String?>(
            isExpanded: true,
            value: _selectedCameraId,
            hint: const Text('Auto-detect (signal-based)'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Auto-detect (signal-based)'),
              ),
              for (final cam in _cameras)
                DropdownMenuItem<String?>(
                  value: cam.id,
                  child: Text('${cam.id} (${cam.lensType})'),
                ),
            ],
            onChanged: locked ? null : _selectCamera,
          ),
          const SizedBox(height: 8),
          LabelRow('Locked lens', resolvedLabel),
        ],
      ),
    );
  }

  Widget _debugPanel() {
    final config = ref.watch(sessionConfigProvider);
    final notifier = ref.read(sessionConfigProvider.notifier);
    final policy = config.policy;
    final acceptance = config.acceptance;

    return SectionCard(
      title: '[debug] tuning',
      child: ExpansionTile(
        // Neutral collapse-control title — `SectionCard`'s `title` above is
        // the sole "[debug] tuning" header; this avoids showing the string
        // twice.
        title: const Text('Tuning knobs'),
        initiallyExpanded: _debugExpanded,
        onExpansionChanged: (v) => setState(() => _debugExpanded = v),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Session policy (note 09)', style: TextStyle(fontWeight: FontWeight.bold)),
                _intField('Warm-up (s)', policy.warmupDuration.inSeconds, notifier.setWarmupSeconds),
                _intField('Silence window (s)', policy.silenceWindow.inSeconds, notifier.setSilenceSeconds),
                Row(
                  children: [
                    const Text('SQI floor:'),
                    const SizedBox(width: 8),
                    DropdownButton<SignalQuality>(
                      value: policy.sqiFloor,
                      items: [
                        for (final q in SignalQuality.values)
                          DropdownMenuItem(value: q, child: Text(q.name)),
                      ],
                      onChanged: (v) {
                        if (v != null) notifier.setSqiFloor(v);
                      },
                    ),
                  ],
                ),
                const Divider(),
                const Text('RR-gate (note 12)', style: TextStyle(fontWeight: FontWeight.bold)),
                _intField('minRrMs', acceptance.minRrMs, notifier.setMinRrMs),
                _doubleField('consistencyThreshold', acceptance.consistencyThreshold, notifier.setConsistencyThreshold),
                _intField('coldStartBeats', acceptance.coldStartBeats, notifier.setColdStartBeats),
                _intField('medianWindow', acceptance.medianWindow, notifier.setMedianWindow),
                const SizedBox(height: 8),
                const Text(
                  'Applies on the next Start.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Value-keyed re-seed pattern (must carry over unchanged from
  /// `streams_screen.dart`): `key: ValueKey('$label-$value')` bound to the
  /// *provider-derived* value + `initialValue: value.toString()`, so submit
  /// → notifier write → rebuild → new key → new `initialValue` re-seeds the
  /// field to the round-tripped provider value. A plain `initialValue`
  /// without the value-keyed `ValueKey` would show stale text after submit.
  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('$label-$value'),
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onFieldSubmitted: (text) {
                final parsed = int.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
              onEditingComplete: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doubleField(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: ValueKey('$label-$value'),
              initialValue: value.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onFieldSubmitted: (text) {
                final parsed = double.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
              onEditingComplete: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}
