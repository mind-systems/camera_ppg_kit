# Example — Shared Widget Kit (neiry-craft parity)

**Date:** 2026-07-03
**Source:** user direction ("keep our dev tools in one style — it should read through our products, even developer ones"); neiry_kit example UI study; notes 21/22 (the screens that will consume it)

## Key Findings

- Neiry's example is pleasant **without a design system** — plain Material 3 defaults, made polished by four things applied *consistently everywhere*: card-section composition, thorough async-state handling, semantic color-coded status, and small extracted row widgets. Match that; do **not** build a token/theme system.
- Our example screens (`source_screen.dart`, `kit_api_tab.dart`, `calibration_screen.dart`) use raw `Container`/`Chip`/`ExpansionTile` with inline colors and `.value ?? default` (no loading/empty/error states) — below that bar.
- **No `ThemeData` (deliberate).** Neiry ships none; theming only camera_ppg's example would make it *diverge* from neiry, i.e. less consistent across our kits, not more. Consistency comes from shared **patterns**.
- This task is the **foundation** — it ships the widgets; the per-screen rebuilds (notes 26–28) consume them.

## Details

### New — `example/lib/widgets/`

Small, dependency-free building blocks mirroring neiry's private row widgets, shared here because three screens repeat the same patterns:

- **`SectionCard({String title, String? subtitle, required Widget child})`** — `Card` → `Padding(EdgeInsets.all(16))` → `Column(crossAxisStart)` with a bold header, an optional grey hint subtitle, `SizedBox(8)`, then `child`. The 16/12/8 rhythm lives here.
- **`MetricRow(String label, num? value, {String unit = '', int decimals = 3, double labelWidth = 140, Color? valueColor, bool mono = false})`** — aligned label→value row; `'—'` when null; `fontFamily: 'monospace'` when `mono` (for live numbers). `EdgeInsets.symmetric(vertical: 4)`.
- **`LabelRow(String label, String value)`** — label→string value (enum display).
- **`StatusChip(String label, Color color)`** — `Chip` with `color.withValues(alpha: 0.15)` background + colored bold label. Replaces the inline chip pattern in `source_screen`/`kit_api_tab`.
- **`StateBanner(String label, Color color)`** — the bordered tinted container currently inlined in `source_screen.dart:_stateBanner` / `kit_api_tab.dart` — extracted verbatim.
- **Async-state helpers** — `AsyncLoader` / `AsyncEmpty(message)` / `AsyncError(error)` (centered icon + text), so screens render real `.when(loading/error/data)` and empty ("waiting for signal…") states instead of `.value ?? default`.
- **A local `statusColor(...)` map** — good→green, fair→orange, poor→red, idle→grey, pending→blue — used by `StatusChip`/`StateBanner`. Kept local to `widgets/`, **not** a global token file.

### Conventions the rebuilds follow (match neiry)

- Every screen = `ListView(padding: EdgeInsets.all(16))` of `SectionCard`s, `SizedBox(12)` between.
- Live numbers monospace; nulls `'—'`; helper/timestamps grey `fontSize: 12`; buttons full-width + semantic (`ElevatedButton` primary / `OutlinedButton` secondary / `FilledButton.tonal` tertiary).

## Guards

- No new dependencies; no `ThemeData` (M3 default — parity with neiry).
- Foundation only: kit `lib/` untouched; the screens are rebuilt in notes 26–28, not here.

## Verify

- The widgets compile; a throwaway smoke screen built from `SectionCard` + `MetricRow` + `StatusChip` renders with the 16/12/8 rhythm and monospace numbers.
