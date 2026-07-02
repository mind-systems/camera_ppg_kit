# Plan Review: Neiry-mirror source shell + Source screen

**Plan:** `.ai-factory/plans/13-neiry-mirror-source-shell-source-screen.md`
**Spec:** `.ai-factory/notes/22-neiry-mirror-source-shell.md` (governing), notes 14/15/16/19/21
**Files Reviewed:** plan (4 tasks) against `example/lib/main.dart`, `screens/kit_api_tab.dart`, `services/camera_ppg_service.dart`, `providers/*`, `auto_detect/auto_detect_screen.dart`, `calibration/calibration_recorder.dart`, kit barrel, ROADMAP line 48
**Risk Level:** 🟢 Low — no blockers; a few non-blocking correctness/maintainability recommendations

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** ✅ Aligned. Task 1's claim that `RrAcceptance`/`SessionPolicy` are importable from the barrel (no `src/` import) is correct — barrel lines 17–18 export them as `[debug]` extras, and `kit_api_tab.dart:1` already consumes them that way. The kit `lib/` guard is respected; all four tasks touch `example/` only. WARN: no `RULES.md` present (optional); no `.ai-factory/skill-context/aif-review/SKILL.md` present (optional) — nothing to enforce.
- **Roadmap (`ROADMAP.md` line 48):** ✅ Aligned. Contract line names exactly these files (`main.dart`, new `screens/source_screen.dart`, new `providers/session_config_provider.dart`, `kit_api_tab.dart`), the `sessionConfigProvider` holding `RrAcceptance`/`SessionPolicy` "applied on restart", the "strip Kit-API to a pure `ref.watch` consumer" outcome, and "entering Raw stops the kit source." Deferring the Calibration branch to the next milestone (line 49 / note 21) is correct scoping — Calibration is its own roadmap item, so no placeholder here is right.
- **Guards:** ✅ Service (note 16), recorder (note 20), stream/service providers, and `auto_detect_screen.dart` are all listed untouched and the plan only *commands* the service — consistent with the codebase. Verified the recorder reads `sessionConfigProvider`'s `acceptance`/`policy` shape the plan defines, so the note-21 "honesty link" will line up.

## Critical Issues

None. The core architecture is sound: `IndexedStack` keeps all three branches mounted, the `CameraPpgService` singleton remains the sole lifecycle owner, and the single "enter Raw → `stopMeasurement()`" hook is the correct minimal exclusivity boundary (verified `AutoDetectScreen` holds **no** long-lived `CameraController` — its camera lifecycle is fully contained inside the awaited `detectCoveredCamera` round-trip and `StreamInspectorScreen` is a pushed route, so keeping Raw mounted never holds the camera while a kit screen is active).

## Recommendations (non-blocking)

### 1. Identify the Raw branch by a named constant/enum, not a magic index — protect the "one-line change" claim
Task 3 sets `children: [SourceScreen, KitApiTab, AutoDetectScreen]` (Raw at index 2) and gates the exclusivity hook on "newly-selected branch is Raw." The plan also promises "adding a fourth branch later is a one-line change." But note 22 (line 27) places the future **Calibration** branch *before* Raw (`Source / Kit-API / Calibration / Raw`). If the hook is written as `if (index == 2)`, inserting Calibration at index 2 in the next milestone silently makes the hook fire on **Calibration** (wrong — stops a running source the calibration screen depends on) and *not* on Raw (now index 3, contention returns). Recommend the plan explicitly require identifying Raw via a named branch identifier (enum or `static const _rawIndex`, or matching the destination, computed from the children list) so inserting Calibration stays a genuine one-line, index-shift-safe change. This is the one item I'd most want pinned before implementation.

### 2. Clarify "reuse" vs. "relocate" for the status helpers
Task 2 says the Source screen should "reuse `_stateBanner(state)` and `_qualityAndPresenceRow()`," while Task 4 explicitly *keeps* `_stateBanner` and `_qualityAndPresenceRow` in `kit_api_tab.dart`. Since these are private methods, they cannot be literally shared — both screens will hold their own copies. That is fine (both screens legitimately display live status), but it contradicts the plan's own "relocated, not duplicated" framing, which applies only to Start/Stop/permission/camera/`[debug]`. Recommend stating outright that the status-display helpers are **intentionally duplicated** (display-only, no lifecycle) while lifecycle/control is relocated, so the implementer doesn't try to factor them out or accidentally strip them from Kit-API.

### 3. `[debug]` field re-seed on provider write — confirm the `ValueKey` pattern is carried over
Task 2 moves the tuning fields to seed from `ref.watch(sessionConfigProvider)` and write via the notifier. The existing `_intField`/`_doubleField` rely on `key: ValueKey('$label-$value')` + `initialValue` to re-seed a `TextFormField` when the backing value changes (submit → notifier → rebuild → new key → new `initialValue`). This works with a provider-backed value exactly as it did with `setState` locals, **but only if the `ValueKey`-keyed-on-value pattern is preserved**. Recommend the plan call this out explicitly (keep `ValueKey('$label-$value')` bound to the provider-derived value) so the field actually reflects an edit after it round-trips through the provider — a plain `initialValue` without the value-keyed `ValueKey` would show stale text after submit.

### 4. AppBar / SafeArea inconsistency across branches (cosmetic)
The old `_TabShell` gave every tab a shared `AppBar` ("Camera PPG Kit"). Task 3's new shell is a `Scaffold` with only a `bottomNavigationBar` and no `AppBar`. `AutoDetectScreen` (Raw) carries its *own* `Scaffold` + `AppBar`, so Raw will show a title bar while Source and Kit-API (which use bare `SafeArea`/`ListView`) will not — and Raw becomes a nested `Scaffold` inside the shell `Scaffold`. This is functional (nested scaffolds are legal; the bottom nav still renders once from the outer shell) but visually uneven. Recommend the plan decide whether the shell provides a top `AppBar` (per-branch title) and confirm the new Source screen wraps its body in `SafeArea` like Kit-API does.

### 5. Stale doc comments in the untouched provider files (cosmetic)
`camera_ppg_service_provider.dart` ("for the example app's Kit-API tab") and `stream_providers.dart` (references "the Kit-API tab shows…") will read inaccurately once lifecycle ownership moves to the Source screen. These are guard files (correctly untouched), so this is not actionable in this milestone — just noting the drift so a future doc pass can catch it. No change required here.

### 6. Acknowledged residual race, now reversed (edge, dev instrument)
The old shell documented an accepted race (leaving Kit-API fires an un-awaited `stopMeasurement()` that can collide with an immediate Raw Start). The new hook reverses the guarded direction (enter Raw → stop kit), which cleanly covers the common case. The symmetric residual remains: if a user triggers Raw's multi-second probe round-trip and, *while it is still running*, switches to Source and presses Start, Raw's in-flight round-trip still holds the camera and the kit's open could hit a `CameraException`. This mirrors the previously-accepted residual and is very unlikely on a developer instrument, but since the direction is now inverted it is worth one sentence in the plan acknowledging it as a known, accepted edge (the shell cannot cheaply cancel Raw's in-flight round-trip).

## Positive Notes

- Correctly identifies that the load-bearing property is *all screens stay mounted + service is sole owner*, not the router package, and justifiably avoids pulling `go_router` into the example (note 22 explicitly permits the `Scaffold`+`NavigationBar`+`IndexedStack` realization).
- Preserves the subtle `done`-recovery path (`stopMeasurement()` before restart from the terminal `done` state) and the `isRunning`/`canStop` derivation when relocating Start/Stop — these encode real prior review findings and the plan carries them intact.
- `sessionConfigProvider` as the single source of truth is aligned end-to-end: the Source panel writes it, `startMeasurement` reads it, and the future calibration screen (note 21) reads the *same* provider to keep the exported JSON honest — the plan keeps this a single provider rather than duplicating config state.
- Scope discipline is good: Calibration branch explicitly deferred to its own milestone, kit `lib/` and the service left untouched, and the exclusivity boundary reduced to exactly one hook.
- Logging plan follows the example convention (`ppgTap`/`ppgLog`, coarse milestones) per CLAUDE.md, and testing/docs are correctly marked "no" for an example-app UI refactor.

Overall this plan is implementable as written; the recommendations above (especially #1) would harden it and keep the forward-compatibility promise honest. No blocking issues.
