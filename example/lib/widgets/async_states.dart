import 'package:flutter/material.dart';

import 'status_color.dart';

/// Centered loading indicator with an optional [caption]. Layout-only — no
/// Riverpod import; the screens own the `AsyncValue.when(...)` wiring.
class AsyncLoader extends StatelessWidget {
  const AsyncLoader({super.key, this.caption});

  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (caption != null) ...[
            const SizedBox(height: 8),
            Text(caption!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

/// Centered "nothing here yet" state — e.g. waiting for signal.
class AsyncEmpty extends StatelessWidget {
  const AsyncEmpty(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_empty, color: Colors.grey),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

/// Centered error state — icon + [error]'s string form, in the poor/red
/// semantic color.
class AsyncError extends StatelessWidget {
  const AsyncError(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: poorColor),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: const TextStyle(color: poorColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
