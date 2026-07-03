import 'package:camera_ppg_kit/camera_ppg_kit.dart';
import 'package:flutter/material.dart';

/// Local semantic status-color palette for the example's widget kit.
///
/// Deliberately **not** a global token/theme file (spec Guards) — just the
/// five named colors already inlined across the screens, collected once so
/// [StatusChip]/[StateBanner] callers and [qualityColor] share one source.
const Color goodColor = Colors.green;
const Color fairColor = Colors.orange;
const Color poorColor = Colors.red;
const Color idleColor = Colors.grey;
const Color pendingColor = Colors.blue;

/// Maps a [SignalQuality] (or `null`, meaning "not yet known") onto its
/// semantic color — the exact switch inlined in every screen's
/// `_qualityAndPresenceRow`.
Color qualityColor(SignalQuality? quality) => switch (quality) {
      SignalQuality.good => goodColor,
      SignalQuality.fair => fairColor,
      SignalQuality.poor => poorColor,
      null => idleColor,
    };
