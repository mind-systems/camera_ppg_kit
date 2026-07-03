# Code Review: Expose which camera auto-detect locked

**Scope:** `git diff HEAD` — `lib/src/api/camera_ppg_session.dart`, `example/lib/screens/source_screen.dart` (plus plan/planner artifacts, not reviewed for code).
**Risk level:** 🟢 Low — one non-blocking cosmetic finding.

## Summary

The change is a faithful, correct implementation of the plan. The kit gains a `resolvedCamera` getter, a `resolvedCameraStream`, a `_setResolvedCamera` mutator (deduped like `_setState`), and a shared `_toCameraInfo` edge-mapper; the lens is set on the single successful lock site and cleared in `_release()`. The example Source screen renders the locked lens as text. Boundary discipline holds — no `CameraDescription`/`camera` type crosses the barrel, and no `flutter`-importing getter was added to the service.

I verified the correctness-critical paths:

- **No stale-lens leak on failure/abandon.** `_setResolvedCamera(_toCameraInfo(description))` is called only in the success promotion block (immediately before `lockedAndStreaming = true`), and every failure/abandon path routes through `_release()`, which clears it to `null`. A failed `start()` never leaves a non-null lens.
- **No concurrency window.** The set happens with no `await` between the last `stale()` check (`camera_ppg_session.dart:361`) and promotion, so it is atomic with `lockedAndStreaming = true`; a concurrent `stop()` either was caught by the stale check (abandon → stays null) or the outer `finally` skips `_release()` because `lockedAndStreaming` is true.
- **Controller lifecycle.** `_resolvedCameraController` is constructed in the initializer list and closed in `dispose()` after `_release()` runs — `_setResolvedCamera(null)` inside `_release()` always fires on a still-open controller, guarded by `!isClosed`.
- **Dedupe semantics.** Deduping on `id` (and `null`) is safe: enumeration ids are unique per device, and clear→relock of the same lens still emits because `_release()` sets null in between.
- **Barrel.** No export change needed — `camera_ppg_kit.dart` already re-exports the whole session file and `camera_ppg_camera_info.dart`. Confirmed.
- **`LabelRow('Locked lens', resolvedLabel)`** matches the widget's `(String label, String value)` signature (`metric_row.dart:52-58`).

## Findings

### 1. [Low / cosmetic] "Locked lens: auto-detecting…" is shown during teardown, not just during the probe

`example/lib/screens/source_screen.dart:315-319`

```dart
final resolvedLabel = !locked
    ? '—'
    : resolved != null
        ? '${resolved.id} (${resolved.lensType})'
        : 'auto-detecting…';
```

The `else` branch assumes "locked but not yet resolved" always means the pre-lock probe is running. That is not the only such window. In `CameraPpgService.stopMeasurement()` (`camera_ppg_service.dart:226-240`) the service emits the `stopping` lifecycle and then nulls `_session` **before** awaiting `session.dispose()`. So during the `stopping` window, `session?.resolvedCamera` is already `null` while `locked` (`lifecycle != SourceLifecycle.idle`) is still `true` — the row renders **"Locked lens: auto-detecting…"** while the banner reads "Stopping…". Nothing is auto-detecting during teardown; the label is misleading.

Impact is cosmetic and confined to a sub-second window in a developer-only example screen (the sibling `_previewCard()` degrades to its neutral placeholder in the same window, so it is not wrong, just empty). This matches the plan's literal three-state spec, so it is a spec-faithful implementation of a slightly incomplete state model rather than a deviation — but it is a genuine display inaccuracy worth one line to fix deliberately.

**Suggested fix:** gate the transient text on the specific pre-lock phase instead of "any locked state" — e.g. render `'auto-detecting…'` only when `lifecycle == SourceLifecycle.starting`, and fall back to `'—'` for `stopping`. This requires threading `lifecycle` (already available in `build()` at `source_screen.dart:125`) into `_cameraOverrideCard` rather than only the derived `locked` bool.

## Notes (no action needed)

- The stale `_cameraOverrideCard` dartdoc that the milestone explicitly cited (old lines 306-310, "the current barrel exposes no such accessor") was correctly rewritten to describe the new behavior.
- Adding `resolvedCameraStream` even though the example consumes only the synchronous getter is not over-engineering — the governing spec (note 36) explicitly asks for a watchable notifier for real hosts (`mind_mobile`), which subscribe once and cannot poll a getter on a lifecycle rebuild.
