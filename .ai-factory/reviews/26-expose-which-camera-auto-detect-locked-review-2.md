# Code Review (pass 2): Expose which camera auto-detect locked

**Scope:** `git diff HEAD` — `lib/src/api/camera_ppg_session.dart`, `example/lib/screens/source_screen.dart`.
**Risk level:** 🟢 Clean.

## What changed since review-1

The single review-1 finding (the teardown-window label) was fixed. `_cameraOverrideCard` now receives the full `SourceLifecycle` instead of a derived `locked` bool, and the transient text is gated on the precise pre-lock phase:

```dart
Widget _cameraOverrideCard(SourceLifecycle lifecycle) {
  final locked = lifecycle != SourceLifecycle.idle;
  final resolved = ref.read(cameraPpgServiceProvider).session?.resolvedCamera;
  final resolvedLabel = resolved != null
      ? '${resolved.id} (${resolved.lensType})'
      : lifecycle == SourceLifecycle.starting
          ? 'auto-detecting…'
          : '—';
```

State coverage is now correct across the whole lifecycle:
- `resolved != null` → `id (type)` — the lens is set before `warmup`, so this covers warmup/measuring/poorSignal.
- `resolved == null && starting` → `auto-detecting…` — the genuine pre-lock probe window only.
- `resolved == null && stopping` → `—` — the teardown window (service nulls `_session` before awaiting `dispose()`) no longer mislabels as "auto-detecting…".
- `resolved == null && idle` → `—`.

`locked` is still derived and still gates the dropdown/Refresh (`onChanged: locked ? null : _selectCamera`), so the disable behavior is unchanged. The call site (`source_screen.dart:144`) passes the `lifecycle` already obtained via `ref.watch(lifecycleProvider)` in `build()` — the read of `resolvedCamera` rides that same rebuild, matching `_previewCard()`. The rewritten dartdoc accurately documents the gating rationale.

## Re-verification of the unchanged kit surface

The `camera_ppg_session.dart` changes are identical to review-1 and remain correct:
- **No stale-lens leak** — `_setResolvedCamera(_toCameraInfo(description))` fires only in the success promotion block; every failure/abandon path routes through `_release()`, which clears to `null`.
- **Atomic with promotion** — no `await` between the last `stale()` check and the set, so a concurrent `stop()` cannot strand a lens.
- **Controller lifecycle** — constructed in the initializer list, closed in `dispose()` after `_release()`; emits guarded by `!isClosed`.
- **Boundary discipline** — `_toCameraInfo` is the sole edge-mapper; no `CameraDescription`/`camera` type crosses the barrel. No `flutter` getter added to the service.
- **Dedupe** — deduping on `id`/`null` is safe; clear→relock of the same lens still emits because `_release()` sets `null` in between.

No new issues introduced. No migrations, type mismatches, or race conditions. The implementation now fully matches the plan and the governing spec (note 36).

REVIEW_PASS
