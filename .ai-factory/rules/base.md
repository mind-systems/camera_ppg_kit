# Project base rules

> Auto-detected conventions from the Flutter-plugin scaffold and the `neiry_kit` sibling. Edit as needed.

## Naming Conventions

- Files: `snake_case.dart` (Dart/Flutter convention; e.g. `rr_interval.dart`, `device_locator.dart`).
- Classes / enums: `PascalCase`.
- Variables / functions / parameters: `lowerCamelCase`.
- Constants: `lowerCamelCase` (Dart `const`), not SCREAMING_CASE.
- Native: Kotlin under `com.mind.camera_ppg_kit`; Swift plugin class `CameraPpgKitPlugin`.

## Module Structure

- Public API surface is the `lib/camera_ppg_kit.dart` barrel — re-export from `lib/src/` only; never let consumers import `src/` directly.
- `lib/src/api/` — high-level Dart API the host calls.
- `lib/src/models/` — value types crossing the API boundary.
- `lib/src/channel/` — method/event-channel names and shared enums.
- `lib/src/processing/` — Dart-side signal/acceptance logic layered on `flutter_ppg`.
- `lib/src/util/` — internal helpers (logging).
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
