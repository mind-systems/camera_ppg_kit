import 'package:flutter/material.dart';

/// The bordered, tinted full-width banner extracted verbatim from
/// `source_screen.dart:_stateBanner` — a [Container] with a low-alpha [color]
/// fill, a [color] border, rounded corners, and a centered bold [label] in
/// [color]. Enum-agnostic: callers resolve the color and pass it in.
class StateBanner extends StatelessWidget {
  const StateBanner(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
}
