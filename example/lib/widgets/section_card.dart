import 'package:flutter/material.dart';

/// The 16/12/8 card rhythm carrier — `Card` → `Padding(16)` →
/// `Column(start)` with a bold header, an optional grey hint, then [child].
///
/// Extracted so the screen rebuilds (notes 26–28) share one card shape
/// instead of re-inlining the same `Card`/`Padding`/`Column` scaffold.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
