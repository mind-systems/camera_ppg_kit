# Plan Review 2: Neiry-mirror source shell + Source screen

**Plan:** `.ai-factory/plans/13-neiry-mirror-source-shell-source-screen.md`
**Spec:** `.ai-factory/notes/22-neiry-mirror-source-shell.md` (governing), notes 14/15/16/19/21
**Files Reviewed:** plan (4 tasks) against `example/lib/main.dart`, `screens/kit_api_tab.dart`, `services/camera_ppg_service.dart`, `providers/stream_providers.dart`, `providers/camera_ppg_service_provider.dart`, kit barrel, `.ai-factory/ARCHITECTURE.md`, `ROADMAP.md` line 47
**Risk Level:** 🟢 Low — no blockers; every prior-review recommendation is now folded in, and one cosmetic maintainability note remains.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** ✅ Aligned. Task 1's claim that `RrAcceptance`/`SessionPolicy` import from the barrel (no `src/` import) is confirmed — barrel lines 17–18 (`export 'src/processing/rr_acceptance.dart' show RrAcceptance;` / `session_policy.dart show SessionPolicy;`) and the ARCHITECTURE "Dependency Rules" deliberate exception (line 41) both spell this out as `[debug]`-tagged extras. All four tasks touch `example/` only; the kit `lib/` guard holds. No `RULES.md`, no `skill-context/aif-review/SKILL.md` present (both optional) — nothing extra to enforce.
- **Roadmap (`ROADMAP.md` line 47):** ✅ Aligned. The contract line names exactly the four files (`main.dart`, new `screens/source_screen.dart`, new `providers/session_config_provider.dart`, `kit_api_tab.dart`), the `sessionConfigProvider` holding `RrAcceptance`/`SessionPolicy` ("knobs applied on restart"), the "strip Kit-API to a pure `ref.watch` consumer" outcome, the "entering Raw stops the kit source" exclusivity exception, and the guards (kit `lib/`, recorder note 20, service note 16 untouched). Deferring the Calibration branch to the next roadmap item (line 48 / note 21) is correct scoping.
- **Governing spec (note 22) + note 21 honesty link:** ✅ Aligned. The plan realizes note 22's load-bearing property (all screens mounted via `IndexedStack` + `CameraPpgService` as sole lifecycle owner) with the note-permitted `Scaffold`+`NavigationBar`+`IndexedStack` realization instead of `go_router`. `sessionConfigProvider` is kept a single source of truth so note 21's calibration screen reads the *same* in-force config — verified against note 21 §"Precondition"/§"Save", which read `sessionConfigProvider`'s `acceptance`/`policy` shape the plan defines.

## Resolution of Prior Review (review 1)

All six recommendations from `...-plan-review-1.md` are now incorporated:

1. **Enum, not magic index (the flagged #1)** — Task 3 now mandates an ordered `_Branch { source, kitApi, raw }` enum driving both `IndexedStack` children and `NavigationBar` destinations, and gates the exclusivity hook on `_Branch.raw`, explicitly forbidding `if (index == 2)`. The Calibration-inserted-before-Raw rationale is written out. ✅
2. **Reuse vs. relocate of status helpers** — Scope notes + Task 2/Task 4 now state `_stateBanner`/`_qualityAndPresenceRow` are *intentionally duplicated* (display-only) on both screens, while only lifecycle/control is relocated. ✅
3. **`ValueKey('$label-$value')` re-seed pattern** — Task 2 now requires the value-keyed `ValueKey` bound to the *provider-derived* value + `initialValue`, and explains the submit→notifier→rebuild→new-key→re-seed cycle. Verified this matches the existing `_intField`/`_doubleField` in `kit_api_tab.dart:494–542`. ✅
4. **AppBar / SafeArea consistency** — Task 3 now gives the shell `Scaffold` a single `AppBar` with a per-branch title and requires the Source screen to wrap its body in `SafeArea`; the nested-`Scaffold` render from Raw's own `AppBar` is explicitly accepted as legal. ✅
5. **Stale doc drift in untouched provider files** — captured under "Untouched-provider doc drift" in Assumptions/Scope, flagged for a future doc pass, correctly not actioned. ✅
6. **Reversed residual race** — captured under "Raw-in-flight residual race (known, accepted)" as a one-paragraph acknowledgement. ✅

## Correctness / API verification

- `service.startMeasurement({cameraId, policy, acceptance})`, `stopMeasurement()`, `availableCameras()` signatures match `camera_ppg_service.dart:92–169`. The `done`-recovery path (Task 2) — `stopMeasurement()` before restart from terminal `done` — matches `kit_api_tab.dart:146–153` and the service re-entry guard (`_measuring`, line 98). ✅
- Provider names the plan relocates/keeps (`cameraPpgServiceProvider`, `stateProvider`, `qualityProvider`, `fingerPresenceProvider`, `rrProvider`, `bpmProvider`) all exist as named in `stream_providers.dart` / `camera_ppg_service_provider.dart`. ✅
- The Task 1 mutator set (`setWarmupSeconds`/`setTargetSeconds`/`setSilenceSeconds`/`setSqiFloor`/`setMinRrMs`/`setConsistencyThreshold`/`setColdStartBeats`/`setMedianWindow`) maps 1:1 onto the real `SessionPolicy` (`warmupDuration`/`targetDuration`/`silenceWindow`/`sqiFloor`) and `RrAcceptance` (`minRrMs`/`consistencyThreshold`/`coldStartBeats`/`medianWindow`) fields seen in `kit_api_tab.dart:101–113`. Seeding from `SessionPolicy()`/`RrAcceptance()` defaults (never inventing numbers) matches the existing `initState` pattern (`kit_api_tab.dart:61–70`). ✅
- Task 4's kept surface (`_stateBanner`, `_qualityAndPresenceRow`, `_bpmSection`, `_rrSection`, the `_rrHistory` rolling list cleared on `warmup` via the existing `ref.listen`) exactly matches what is display-only in `kit_api_tab.dart`; the removal list (`_start`/`_stop`/`_startStopRow`, permission, camera override, `_lastError`/`_errorBanner`, `[debug]` fields + `_debugPanel`/`_intField`/`_doubleField`/`_buildPolicy`/`_buildAcceptance`, `permission_handler` import) is complete and consistent with keeping it a `ConsumerStatefulWidget` for `_rrHistory`. ✅
- Raw-exclusivity hook placement in `onDestinationSelected` correctly fires on *entering* Raw (tap), replacing the old `_onTabChanged` "leaving Kit-API → stop" rule (`main.dart:71–88`). The old `SingleTickerProviderStateMixin`/`TabController` teardown is correctly slated for removal. ✅

## Non-blocking observations

### 1. Derive the AppBar title from the branch enum, not a parallel literal list (cosmetic, undercuts the "one-line change" promise slightly)
Task 3 illustrates the per-branch title as `['Source','Kit API','Raw'][index]` — an index-keyed parallel array. This is a *second* index-ordered structure alongside the `_Branch` enum, so inserting the Calibration branch later means editing both the enum-derived children/destinations *and* this title array (and keeping their orders in sync). Since the whole point of recommendation #1 was that inserting Calibration stays a genuine one-line, index-shift-safe change, consider giving each `_Branch` case a `label`/`title` and building the `AppBar` title, the destinations, and the children all from the enum — so there is exactly one ordered source of truth. The plan says "e.g.", so this is illustrative rather than prescriptive, but the parallel array is the one spot that would still need a manual second edit. Trivial, non-blocking.

### 2. `availableCameras()` during a live measurement opens a second transient session (already safe — noting for the implementer)
The Source screen's `_loadCameras()`/Refresh calls `service.availableCameras()`, which spins up a transient `CameraPpgSession` purely to enumerate (`camera_ppg_service.dart:162–169`) — it never opens a controller or torch, so it does not contend with a running measurement's camera. The existing Kit-API code already disables Refresh while `isRunning` anyway; carrying that `_cameraOverrideSection(isRunning)` disable-guard over (as Task 2 implies via "the stale-selection guard") keeps behaviour identical. No change needed — just confirming the transient-session enumeration is not a hidden exclusivity violation.

## Positive Notes

- The plan is now fully self-consistent with the enum-based forward-compatibility promise: `_Branch` gates children, destinations, and the Raw exclusivity hook, making the note-21 Calibration insertion index-shift-safe.
- Scope discipline is excellent: kit `lib/`, the recorder, and `CameraPpgService` are untouched guard files; the Source screen only *commands* the service; the exclusivity boundary is reduced to exactly one narrow hook.
- The subtle prior-review-hardened behaviours (the `done`-recovery `stopMeasurement()` before restart, the `isRunning`/`canStop` derivation, the value-keyed `TextFormField` re-seed) are all carried over intact rather than silently dropped in the relocation.
- `sessionConfigProvider` as a single source of truth is aligned end-to-end (Source panel writes it, `startMeasurement` reads it, note-21 calibration reads the same provider for honest JSON) — no duplicated config state.
- Logging plan follows the example convention (`ppgTap`/`ppgLog`, coarse milestones) per CLAUDE.md; testing/docs correctly marked "no" for an example-app UI refactor.

The plan is implementable as written. The two observations above are cosmetic/confirmatory and do not block implementation.

PLAN_REVIEW_PASS
