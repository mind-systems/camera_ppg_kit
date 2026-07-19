# Project base rules

> Auto-detected conventions from the Flutter-plugin scaffold and the `neiry_kit` sibling. Edit as needed.

## Module Structure

- Public API surface is the `lib/camera_ppg_kit.dart` barrel — re-export from `lib/src/` only; never let consumers import `src/` directly.
- The kit must not import from `mind_mobile`; it depends only on `flutter`, `plugin_platform_interface`, `flutter_ppg`, and `camera`.

## Error Handling

- Cross the platform-channel boundary with typed model values for expected states (permission denied, no finger, poor signal, unsupported device) — do not throw across the channel.
- Reserve exceptions for genuinely exceptional/programmer errors; sentinel/`-1`-style "not yet available" values follow the `neiry_kit` model convention.

## Logging

- No dependency on the app logger facade. Route all plugin logs through a single internal helper (mirror `neiry_kit/lib/src/util/nlog.dart`); keep native logs minimal.

## Dependencies

- Add packages only via `flutter pub add` — never hand-edit `pubspec.yaml`.
- Invoke Flutter as `/usr/local/bin/flutter` from automation.
- This kit owns no `.proto`/wire contract; do not add gRPC here.
