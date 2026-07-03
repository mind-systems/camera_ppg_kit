import 'package:flutter/material.dart';

/// The inline SQI chip extracted from `source_screen`/`streams_screen`'s
/// `_qualityAndPresenceRow` — a [Chip] tinted with [color] at low alpha and a
/// bold [label] in [color]. Enum-agnostic: callers resolve the color (e.g.
/// via `status_color.dart`'s `qualityColor`) and pass it in.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
      visualDensity: VisualDensity.compact,
    );
  }
}
