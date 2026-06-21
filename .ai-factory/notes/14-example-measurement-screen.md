# Example — Developer Playground

**Date:** 2026-06-21
**Source:** ROADMAP Phase 9; neiry `example/` (router.dart, providers/rr_provider.dart, neiry_service_provider.dart, device_state_providers.dart); notes 01 (enumeration), 02 (raw signal/FPS), 07 (session + streams), 08 (camera override), 09 (session policy as settings), 16 (CameraPpgService singleton — planned)

## Key Findings

- There is **one** example app, not two. It is the plugin's `example/` in the classic Flutter-plugin sense: a **developer-facing kitchen-sink** that exercises *every* capability of the kit. Its audience is the **developer integrating the kit** (e.g. whoever wires it into `mind_mobile`), not a wellness end-user. The Phase-2 feasibility panels (notes 01/02) are the *raw first version* of this same app; Phase 9 grows them into the full playground once the kit API/service exists.
- **It tests what the kit ships — nothing more, nothing less.** Every panel exists because it maps to a real shipped capability the host (`mind_mobile`) will consume. If a metric is one nobody downstream would use, it does not belong in the kit and is not tested here. (Audit each item against this lens; today the surface has no vanity metrics.) The app shows (1) live data streams the kit emits and (2) configuration knobs the kit accepts.
- **The warm-up → measuring → poorSignal → done lifecycle is core kit functionality, on by default (note 09) — the host must NOT reimplement it.** The host gets "measure now → trusted result" for free. So the example's first job is to **prove that lifecycle works on real hardware before `mind_mobile` depends on it**: it surfaces `MeasurementState` prominently with a minimal per-state affordance (e.g. a "warming up, hold still…" indicator during `warmup`, a "measuring" indicator, and a clear `done`), and confirms transitions happen on real signal. What it does **not** build is an aggregate **result summary** (mean BPM, HRV, scatter) — that presentation is the host's job, not the kit's. The example proves `done` is reached and (if the kit exposes them) accumulated intervals are retrievable; it does not editorialize them.
- **Two tiers, kept visibly distinct:** the **shipped surface** the host consumes (RR + `isArtifact`, derived BPM, SQI, finger-presence, `MeasurementState`, and host-settable config) is tested because the host relies on it; **debug/tuning affordances** (numeric SNR, FPS, raw waveform, torch/resolution/exposure knobs) exist only to validate and tune, and must be marked debug so they are never mistaken for the consumer contract.
- **Port the neiry stream-ownership lesson:** every stream subscription lives in a Riverpod `StreamProvider` sourced from the service; widgets only `ref.watch(...)`. No `StreamBuilder`, no per-widget `.listen()` — neiry deliberately moved all subscriptions into providers so a rebuild never re-subscribes.
- BPM is **display-only**: `60000 / intervalMs`, derived in the UI/provider from the latest non-artifact `RrInterval`. The kit never emits BPM/HRV (note 07). Do not add a BPM stream to the kit.
- Source streams from `CameraPpgService` (note 16), not directly from `CameraPpgSession` — the example mirrors how `mind_mobile` will consume the kit (service singleton behind a provider).

## Details

### Shape

A single screen, organized as panels (scroll or tabs — implementer's call), all reading one running service:

1. **Live preview** — `CameraPreview` from the service's controller. The preview surface is the one place a `camera` widget is allowed in the example, and only via a service-exposed preview builder — never by reaching a `CameraController` across the barrel (confirm exposure shape against note 16/07).
2. **Stream inspector** — every kit output, live and raw, nothing hidden. Tag each as `[shipped]` (host consumes it) or `[debug]` (validation/tuning only):
   - `[shipped]` `rrStream`: latest RR (ms) + a rolling sparkline/list of recent intervals; **`isArtifact` shown, not filtered out** (a developer wants to see rejected beats).
   - `[shipped]` derived **BPM** (large, display-only) from the latest non-artifact interval.
   - `[shipped]*` `qualityStream`: SQI chip (Good/Fair/Poor). *Conscious keep, not inertia:* the host's `ActiveRrSource` RR contract does **not** read it (confirmed — note 19); SQI's real consumers are *internal* (drives `MeasurementState.poorSignal`, note 09) and the host's UI-guidance layer ("press your finger"). Cheap and plausibly useful → kept deliberately.
   - `[shipped]` **finger-presence** boolean indicator.
   - `[shipped]` `stateStream`: current `MeasurementState`, shown prominently **with a per-state affordance** — `warmup` → "warming up, hold still…"; `measuring` → live indicator; `poorSignal` → guidance; `done` → "measurement complete". This is the lifecycle the host gets by default and the thing the example most needs to prove works.
   - `[debug]` numeric **SNR** (the scalar behind SQI — helps a developer see *why* quality dropped; host consumes SQI, not raw SNR).
   - `[debug]` **measured FPS** (the FPS-sensitivity instrument from note 02 — keep it visible here, where `CameraPreview` + rebuilds are exactly what can starve frames).
   - `[debug]` **red-channel waveform** (raw/filtered pulse wave) from a `[debug]`-tagged `debugSignalStream` of `List<double>` (note 07). **Justified, kept** — not a pretty curve but the *primary* diagnostic for the Phase-2 question "does this phone produce a usable optical PPG at all?": finger contact, saturation, and pulse visibility read off the wave in a second, faster and surer than SNR/SQI numbers. Crosses as `List<double>`, never `PPGSignal`/`CameraImage`, so it does not break the barrel (note 07/19); absent from the consumer freeze.
3. **Settings playground** — every knob the kit's API accepts, live-editable. Same two-tier tagging:
   - `[shipped]` **Camera selection/override** — folds in the note-01 auto-detect panel: show which sensor auto-detect locked onto, list the selectable rear sensors (id + lens type + `flashAvailable`), and let the developer pin one via `useCamera` (note 08) before `start()` to skip auto-detect.
   - `[shipped]` **Warm-up window** duration and **target duration** — these are the lifecycle's tunables (note 09); the host may set them, so they are part of the surface. The example must show that the **defaults work with zero configuration** (prove warm-up→done out of the box), then let the developer retune.
   - `[debug]` **Torch** on/off.
   - `[debug]` **Resolution preset** and **exposure-lock** toggle (note 02 setup knobs — kit-internal tuning, used to find good defaults, not host-set config).
   - `[debug]` **Acceptance-gate params** — lower-bound ms, deviation %, cold-start grace beats, median window — a **read-WRITE** panel that constructs the session with a custom `RrAcceptanceConfig` (note 12). These are *not* host config (the host never tunes "40% consistency" — note 19), but we do **not** yet know the right values for camera PPG (neiry's come from chest PPG, a different noise profile), so the spike (Phase 2/8) must tune them live. After the spike, good numbers become the new internal defaults; the ctor param stays for tests/re-tuning but is absent from the consumer freeze.
   - `[debug]` **Show raw vs gated RR** toggle.
4. **Start/Stop** — starts/stops the measurement (camera + stream subscriptions on the service). "Stop" is idle, not a results screen.

### `example/lib/` files

- `main.dart` — wrap `MyApp` in `ProviderScope`; `MaterialApp.router(routerConfig: appRouter)`.
- `router.dart` — `go_router` with `initialLocation: '/playground'`, a single `GoRoute`. No `StatefulShellRoute` (single screen).
- `providers/camera_ppg_service_provider.dart` — `Provider<CameraPpgService>` returning the singleton (note 16), `ref.onDispose(s.dispose)` — shape of neiry's `neiry_service_provider.dart`.
- `providers/stream_providers.dart` —
  - `rrProvider = StreamProvider<RrInterval>((ref) => ref.watch(cameraPpgServiceProvider).rrStream)`
  - `qualityProvider = StreamProvider<SignalQuality>(...qualityStream)`
  - `stateProvider = StreamProvider<MeasurementState>(...stateStream)`
  - `bpmProvider = Provider<int?>((ref) => ref.watch(rrProvider).whenOrNull(data: (rr) => rr.isArtifact ? null : 60000 ~/ rr.intervalMs))` — display-only.
- `providers/settings_providers.dart` — `StateProvider`/notifier per knob; the service reads these (or is re-configured) when the developer changes them.
- `screens/playground_screen.dart` — `ConsumerWidget` composing the four panels above.

### Deps

In `example/`: `flutter pub add flutter_riverpod go_router`. Camera permission flow is **note 15** — reference it, do not duplicate.

### Design decisions (resolved 2026-06-21 — reflected above)

- **Warm-up/duration:** ship **on by default** with concrete defaults (note 09); `[shipped]` tunables; the example proves the zero-config defaults first, then allows retuning.
- **Gate thresholds:** neither `[shipped]` config nor `[debug]` read-only. They stay constructor-injectable with internal defaults in `RrAcceptance` (note 12), reach the playground via an **optional `[debug]` `RrAcceptanceConfig` on `CameraPpgSession`** (host leaves it `null`/absent), and are **absent from the consumer freeze** — note 19 lists this as the *single* debug-tagged optional **input**. One line: injectable for us/tests, defaulted for the host, debug-tunable in the playground, absent from the contract.
- **Waveform:** kept as a justified `[debug]` `debugSignalStream` (`List<double>`) — the primary Phase-2 signal-existence diagnostic. Requires note 07 to stop dropping the red-channel (tap the same `PPGSignal` it already receives); it is a debug-tagged **output**, absent from the freeze.
- **SQI tier:** `[shipped]` but a conscious keep — not read by the host RR contract (confirmed against `active-rr-source.md`); retained as the internal `MeasurementState` driver and for host UI guidance (note 19).

### Verify

On device, the **primary proof** is the kit-owned lifecycle working with default config and no app-side logic: place a finger over the lens + flash → Start → auto-detect locks the covered sensor → state shows `warmup` ("hold still…") with RR withheld → settles to `measuring` with plausible BPM → reaches `done` at the default duration. Pressing Start with no finger placed surfaces the typed `CameraPpgError` and returns to idle (retry prompt), with no torch-strobing loop. Then the rest: streams come alive (RR + `isArtifact`, BPM, SQI, finger-presence, and the `[debug]` SNR/FPS). Lift finger → finger-presence flips, SQI drops, `isArtifact` beats appear, state shows `poorSignal` and recovers. Change camera override → preview switches to the chosen sensor. Retune warm-up/duration → observe the effect on the state transitions and RR forwarding. Hot-restart and tab-away release camera + torch (no torch-stuck), proving provider `onDispose`.

### Guards

- No `StreamBuilder`, no per-widget `.listen()` — subscriptions only in providers.
- No `CameraImage` / `PPGSignal` / `FlutterPPGService` type in example code — only kit models + the sanctioned preview surface.
- BPM/HRV derived in the example only; never pushed into the kit barrel.
- The warm-up→done lifecycle is owned by the **kit** (note 09). The example must **not** reimplement any of it in Dart — it only subscribes to `stateStream` and renders a per-state affordance. If the example needs to add session logic, that logic belongs in the kit instead.
- Every panel must be tier-tagged `[shipped]`/`[debug]` and earn its place against "test what we ship" — if an item maps to no real host-consumed capability and isn't a justified debug aid, drop it (from the kit, not just the example).
- One app, one purpose: a developer playground. No guided wellness UX, no aggregate session-result summary (mean BPM, HRV, scatter) — those belong to the host app (`mind_mobile`), not the kit's example.
