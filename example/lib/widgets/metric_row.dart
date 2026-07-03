import 'package:flutter/material.dart';

/// A fixed-width label followed by a formatted numeric value — `'—'` when
/// [value] is `null`, else `value.toStringAsFixed(decimals)` with [unit]
/// appended (a space only when [unit] is non-empty).
class MetricRow extends StatelessWidget {
  const MetricRow(
    this.label,
    this.value, {
    super.key,
    this.unit = '',
    this.decimals = 3,
    this.labelWidth = 140,
    this.valueColor,
    this.mono = false,
  });

  final String label;
  final num? value;
  final String unit;
  final int decimals;
  final double labelWidth;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '—'
        : '${value!.toStringAsFixed(decimals)}${unit.isNotEmpty ? ' $unit' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: labelWidth, child: Text(label)),
          Text(
            text,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : null,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed-width label followed by a plain string value — for enum display
/// (finger-presence, camera lens, etc.), same row rhythm as [MetricRow] but
/// no numeric formatting.
class LabelRow extends StatelessWidget {
  const LabelRow(
    this.label,
    this.value, {
    super.key,
    this.labelWidth = 140,
  });

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: labelWidth, child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}
