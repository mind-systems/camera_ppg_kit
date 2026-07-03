import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The in-force `[debug]` session configuration (spec notes 09/12/19) — the
/// **single source of truth** the Source screen's tuning panel edits and the
/// future calibration screen (note 21) reads to describe the params that
/// were really running.
///
/// Immutable value type: a knob change never mutates a live [SessionPolicy]/
/// [RrAcceptance] in place, it produces a new [SessionConfig] via
/// [copyWith] that applies on the *next* `startMeasurement` call.
class SessionConfig {
  const SessionConfig({required this.acceptance, required this.policy});

  /// Seeded from the kit's own defaults — never invent numbers here.
  factory SessionConfig.defaults() =>
      SessionConfig(acceptance: RrAcceptance(), policy: SessionPolicy());

  final RrAcceptance acceptance;
  final SessionPolicy policy;

  SessionConfig copyWith({RrAcceptance? acceptance, SessionPolicy? policy}) {
    return SessionConfig(
      acceptance: acceptance ?? this.acceptance,
      policy: policy ?? this.policy,
    );
  }
}

/// Holds the current [SessionConfig] and the granular mutators the Source
/// screen's `[debug]` panel calls on field submit — each rebuilds the
/// relevant `SessionPolicy`/`RrAcceptance` and writes it back via
/// [SessionConfig.copyWith].
class SessionConfigNotifier extends Notifier<SessionConfig> {
  @override
  SessionConfig build() => SessionConfig.defaults();

  // ── SessionPolicy knobs (spec note 09) ──────────────────────────────────

  void setWarmupSeconds(int seconds) {
    final p = state.policy;
    state = state.copyWith(
      policy: SessionPolicy(
        warmupDuration: Duration(seconds: seconds),
        silenceWindow: p.silenceWindow,
        sqiFloor: p.sqiFloor,
      ),
    );
  }

  void setSilenceSeconds(int seconds) {
    final p = state.policy;
    state = state.copyWith(
      policy: SessionPolicy(
        warmupDuration: p.warmupDuration,
        silenceWindow: Duration(seconds: seconds),
        sqiFloor: p.sqiFloor,
      ),
    );
  }

  void setSqiFloor(SignalQuality sqiFloor) {
    final p = state.policy;
    state = state.copyWith(
      policy: SessionPolicy(
        warmupDuration: p.warmupDuration,
        silenceWindow: p.silenceWindow,
        sqiFloor: sqiFloor,
      ),
    );
  }

  // ── RrAcceptance knobs (spec note 12) ────────────────────────────────────

  void setMinRrMs(int minRrMs) {
    final a = state.acceptance;
    state = state.copyWith(
      acceptance: RrAcceptance(
        minRrMs: minRrMs,
        consistencyThreshold: a.consistencyThreshold,
        coldStartBeats: a.coldStartBeats,
        medianWindow: a.medianWindow,
      ),
    );
  }

  void setConsistencyThreshold(double consistencyThreshold) {
    final a = state.acceptance;
    state = state.copyWith(
      acceptance: RrAcceptance(
        minRrMs: a.minRrMs,
        consistencyThreshold: consistencyThreshold,
        coldStartBeats: a.coldStartBeats,
        medianWindow: a.medianWindow,
      ),
    );
  }

  void setColdStartBeats(int coldStartBeats) {
    final a = state.acceptance;
    state = state.copyWith(
      acceptance: RrAcceptance(
        minRrMs: a.minRrMs,
        consistencyThreshold: a.consistencyThreshold,
        coldStartBeats: coldStartBeats,
        medianWindow: a.medianWindow,
      ),
    );
  }

  void setMedianWindow(int medianWindow) {
    final a = state.acceptance;
    state = state.copyWith(
      acceptance: RrAcceptance(
        minRrMs: a.minRrMs,
        consistencyThreshold: a.consistencyThreshold,
        coldStartBeats: a.coldStartBeats,
        medianWindow: medianWindow,
      ),
    );
  }
}

final sessionConfigProvider =
    NotifierProvider<SessionConfigNotifier, SessionConfig>(SessionConfigNotifier.new);
