# Project Rules

> Short, actionable rules and conventions for this project. Loaded automatically by /aif-implement.

## Module Structure

- The kit must not import from `mind_mobile`; it depends only on `flutter`, `plugin_platform_interface`, `flutter_ppg`, `camera`, and `sensors_plus`.

## Error Handling

- Cross the platform-channel boundary with typed model values for expected states (permission denied, no finger, poor signal, unsupported device) — do not throw across the channel.
- Reserve exceptions for genuinely exceptional/programmer errors; sentinel/`-1`-style "not yet available" values follow the `neiry_kit` model convention.

## Logging

- No dependency on the app logger facade. Route all plugin logs through a single internal helper (mirror `neiry_kit/lib/src/util/nlog.dart`); keep native logs minimal.

## Dependencies

- Invoke Flutter as `/usr/local/bin/flutter` from automation.
- This kit owns no `.proto`/wire contract; do not add gRPC here.
