# Code Review — Example: shared widget kit (neiry-craft parity)

**Plan:** `.ai-factory/plans/17-example-shared-widget-kit-neiry-craft-parity.md`
**Reviewed:** `git diff HEAD` — seven new files under `example/lib/widgets/` plus planning artifacts (`.json`, plan `.md`, plan-review `.md`).

## Scope check

Only the seven intended widget files were added; no screen (`source_screen.dart`, `streams_screen.dart`, `calibration_screen.dart`), provider, service, `main.dart`, or kit `lib/` file was touched. The "foundation only, screens untouched" guard holds.

## Verification

- **`flutter analyze example/lib/widgets` → "No issues found!"** — Task 7's claim confirmed; the widgets compile clean under `package:flutter_lints/flutter.yaml`.
- **`SignalQuality` resolves** — exported from the kit barrel via `src/models/signal_quality.dart`; enum has exactly `good`, `fair`, `poor`, so `qualityColor`'s `switch` over those three plus `null` is exhaustive (no runtime `switch` fall-through).
- **Const validity** — `const Color goodColor = Colors.green` (and siblings) are valid compile-time consts; `poorColor` is usable in `const Icon(... color: poorColor)` in `async_states.dart`.

## Correctness notes

Each widget is a stateless, pure-presentation leaf — no state, async, streams, Riverpod, or platform calls — so there is no race, lifecycle, migration, or type-mismatch surface to break at runtime.

- `MetricRow` — `value == null` renders `'—'`; the non-null branch guards `value!` correctly; unit spacing (`' $unit'` only when non-empty) and `mono`/`valueColor` behave as specified.
- `StateBanner` / `StatusChip` — styling is byte-faithful to the inlined `_stateBanner` / `_qualityAndPresenceRow` patterns; kept enum-agnostic (caller passes the color), which is the right seam.
- `SectionCard` — 16/12/8 rhythm matches the spec; optional grey subtitle rendered only when non-null.
- `async_states.dart` — layout-only, sources `poorColor` from `status_color.dart` (resolves the soft Task 5↔Task 1 dependency the plan-review flagged); no unused imports.
- Barrel re-exports all six modules.

## Minor observation (non-blocking, not a defect)

`StatusChip` always sets `visualDensity: VisualDensity.compact`, whereas the original `_qualityAndPresenceRow` SQI chip did not (only the streams RR chips did). This is a cosmetic tightening within the plan's "Optionally `visualDensity: VisualDensity.compact`" allowance — a deliberate style choice, not a bug — and is harmless since no screen consumes the widget yet.

No correctness, security, or runtime issues found.

REVIEW_PASS
