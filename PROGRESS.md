# PROGRESS.md — OpenAgentIsland work log

Chronological log. Newest first within each section. Architecture/design rationale
lives in `NOTES.md`.

---

## Current phase & status

**2026-07-13 (evening): macOS dock — USER-APPROVED.** Magnification (cosine
falloff, +60%, 96px range; centre from BASE width to avoid a binding loop
через implicitWidth), launch bounce, glass tiles behind icons (kitty/zen/
YandexMusic icons are dark and vanished on a dark bar — diagnosed by rendering
the icon files on black), liquid-glass bar (light frosted gradient + gloss +
hairline; dark gradient stops read as black over the dark wallpaper corner),
pin/app-grid buttons removed, round accent dots. Hyprland side (user config,
NOT in repo): `~/.config/hypr/custom/rules.lua` adds blur + ignore_alpha 0.15
for namespace quickshell:dock. Gotchas: (1) layer rules apply at surface MAP
time — after hyprctl reload the quickshell surface must be recreated (any
hot-reload does it); (2) a full-strength StyledRectangularShadow behind
translucent glass reads as a dark smudge — opacity 0.35; (3) user's Hyprland
config is LUA (dots-hyprland): `hl.layer_rule({ match = { namespace = "..." },
blur = true })`, and `hyprctl dispatch` uses hl.dsp.* dispatchers (no
movecursor equivalent found — use ydotool for pointer).

**2026-07-13: Wallpaper picker in the notch (user back on Hyprland).** New
"wallpapers" surface (1200×620) embedding end-4's `WallpaperSelectorContent`
(thumbnails/search/folder nav; apply → switchwall.sh re-themes the island).
Content got a `dismissed()` signal — its close paths only flipped
`GlobalStates.wallpaperSelectorOpen`, meaningless embedded; notch closes the
island on it (Esc/apply/close/fallback-picker). Opened via the new Wallpaper
chip (Widgets tab, Hyprland-gated — switchwall is hyprctl-based) or
`island wallpapers` IPC. The `island` IPC target moved from plasma/shell.qml
into IslandNotch — both editions now share verbs
(dashboard/agent/power/clipboard/wallpapers/close); screen resolution via
focusedScreenName() (falls back to screens[0] on KWin). Verified live on the
user's running Hyprland session via hot-reload + `island wallpapers` + grim.

**2026-07-12: Bluetooth auto-revive after resume (`SleepRestore.qml`).** BT kept
coming back soft-blocked/unpowered after every suspend (adapter re-registers:
fresh rfkill index each wake; no "block" actor visible in journal). Service
watches logind PrepareForSleep on the system bus (dbus-monitor), snapshots
adapter state before sleep, and on wake — only if BT was on — runs
`rfkill unblock bluetooth; bluetoothctl power on` after 3s. Woken eagerly from
plasma/shell.qml (lazy singleton). Real-world verification = next suspend.
Also: both dbus-monitor watchers now stdin-tethered (restarts orphaned them;
orphans self-clean only on next signal write → SIGPIPE).

**2026-07-11 (late): Meta+V → island clipboard page — USER-VERIFIED.** Meta+V
was bound to Klipper's popup, which died when the clipboard applet left the
systray (`/klipper` DBus object gone from plasmashell). New `island clipboard`
IPC verb opens the dashboard straight onto the Clipboard page (one-shot
`Island.dashboardDetail` hint; second press closes).

Binding: **KWin script** (`plasma/kwin-script/oai-shortcuts/`, installed by
`plasma/install-shortcuts.sh`) — `registerShortcut("…", "…", "Meta+V", …)`
runs inside the compositor (same grab path as built-in shortcuts) and
`StartUnit`s the oneshot user unit `oai-clipboard.service` (KWin scripts can't
spawn processes; StartUnit(ss) is the only simple-signature DBus launcher).
Autoloads every login via kwinrc [Plugins] oai-shortcutsEnabled.

DEAD END (do not retry): KGlobalAccel *service* shortcuts
(`[services][x.desktop] _launch=` + doRegister/setShortcut over DBus). The
component registers, persists, and even launches via `invokeShortcut`, but its
key grab stays `isActive: false` until kglobalacceld (inside kwin_wayland)
reloads at login — a live registration-holder client doesn't activate it
either. Also: ydotool-synthesised Meta+V never triggers KWin shortcuts — test
via `/component/kwin invokeShortcut "<name>"` + a real key press.

**2026-07-11 (evening): KDE-panel parity — layout pill, brightness, clipboard.**
The last three gaps for dropping the stock KDE panel:
- **Keyboard layout pill** (`services/KdeKeyboardLayout.qml` + pill in
  IslandRight between perf toggle and clock): KWin's org.kde.KeyboardLayouts
  DBus API; live updates via a `dbus-monitor` subscription to layoutChanged;
  click = switchToNextLayout. Verified live us↔ru on screen. Hidden on
  Hyprland / single-layout.
- **Brightness slider** in Widgets tab next to volume/mic — existing Brightness
  service (brightnessctl), monitor resolved via `pane.QsWindow.window?.screen`
  in Component.onCompleted. Hidden when no backlight.
- **Clipboard history page** — 5th chip opens a centre-column page over the
  existing Cliphist service: click row = copy back (check feedback), per-row
  delete, wipe-all. Cliphist now runs its own `wl-paste --watch cliphist store`
  watchers on Plasma, each tethered to quickshell's stdin pipe (bash wrapper:
  `wl-paste ... & cat >/dev/null; kill $W`) — SIGKILL of qs leaves no orphaned
  watchers (verified; before the tether every restart leaked two). shell.qml
  pokes `Cliphist.refresh()` at startup because lazy singletons don't
  instantiate (and thus don't watch) until first referenced.

**2026-07-11: Night Mode + Caffeine fixed for Plasma.**
- Night Mode chip drove hyprsunset/hyprctl — no-op under KWin (only flipped its
  own flag). New `services/KwinNightLight.qml`: ON = `kwriteconfig6 --notify`
  NightColor Active+Mode=Constant, OFF = Active=false. **Gotcha: without
  `--notify` KWin never applies the change** (its KConfigWatcher listens for
  kconfig change broadcasts; even `org.kde.KWin reconfigure` doesn't reload
  NightColor). Chip state = DBus `currentTemperature < 6000` (real warm state,
  30s poll), so an externally-scheduled night light reads correctly. Verified:
  Mode=Constant with --notify → currentTemperature 6500→4500 on screen.
- Caffeine used Quickshell IdleInhibitor on an invisible 0×0 window — KWin
  honours idle-inhibit only for visible surfaces, so it did nothing. `Idle`
  service now also runs `kde-inhibit --power --screenSaver cat` (stdinEnabled;
  dies with quickshell) while `inhibit` is on, off Hyprland. Verified
  kde-inhibit registers: org.freedesktop.PowerManagement HasInhibit → true.
- Note: PolicyAgent.ListInhibitions does NOT show kde-inhibit entries; use
  PowerManagement.HasInhibit to check.

**2026-07-11: Agent Island folded into the dashboard (Agents tab).** While an
agent ran, every notch click landed on the agent surface — the rest of the
dashboard was unreachable ("не могу получить доступ к остальным функциям").
Now: dashboard has a 4th tab **Agents** hosting `AgentSurface`; a notch click
always opens the dashboard, preselecting Agents when an agent is active
(one-shot `Island.dashboardTab` hint consumed by `DashboardSurface` on create).
The compact agent surface remains only for auto-opened permission cards.
Verified: notch click with active agent → dashboard on Agents tab; tab clicks
switch panes.

**2026-07-11: Permission cards no longer hijack the screen.**
- Auto-opened agent surfaces (pending permission) used to mask the WHOLE monitor
  for click-outside-to-close — with an agent running, the desktop was unclickable
  ("не могу пользоваться остальными функциями"). New `Island.autoOpened` flag:
  auto-opened surfaces mask only the notch body (rest of screen click-through,
  no click-catcher); user-opened surfaces keep full-screen click-to-close.
- Verified with a fake `permission_request` into the bridge socket: card
  auto-opened, outside click did NOT close it, desktop stayed usable (user kept
  watching a video under it), Allow All on the card worked.

**2026-07-11: BT toggle lifts rfkill soft block.** After suspend the adapter was
`off-blocked` (soft rfkill); setting BlueZ Powered silently fails in that state,
so the island's BT toggle looked dead. `pane.toggleBluetooth()` now runs
`rfkill unblock bluetooth && bluetoothctl power on` when enabling. Verified
end-to-end: blocked → dashboard chip click → On.

**2026-07-11: Right-island tray rebuilt for Plasma — verified with real clicks.**
- end-4's bar `SysTray` was unusable inside the narrow island window on KWin:
  every item was "unpinned", so the pill showed only the overflow chevron, whose
  `StyledPopup` positions itself in *bar-window* coordinates (assumes a
  full-width bar window — wrong in the pill-sized island window), and menu
  dismissal relies on `HyprlandFocusGrab` (KWin: "hyprland_focus_grab_v1 not
  supported"). Net effect: tray looked present but nothing worked.
- Replaced with an island-native tray inline in `IslandRight.qml`: all
  `SystemTray.items` rendered directly in the pill (no pin/overflow), left-click
  `activate()` (or menu for `onlyMenu` items), middle-click
  `secondaryActivate()`, right-click opens the SNI menu via **`QsMenuAnchor`** —
  a native popup the compositor positions and dismisses itself (same pattern as
  waffle's `TrayButton`). Works on both KWin and Hyprland.
- Verified via ydotool-injected clicks + screenshots: left-click toggled the
  Telegram window, right-click showed "Открыть/Закрыть Telegram" under the icon,
  outside click dismissed the menu.
- Gotcha: ydotool `mousemove -a` is useless under adaptive pointer accel; fix =
  set flat profile on ydotool's virtual device at runtime
  (`busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/eventNN
  org.kde.KWin.InputDevice pointerAccelerationProfileFlat b true`), then home to
  a screen corner with a huge relative move and step to the target relatively.

**2026-07-10: AI quota tracker + lockscreen polish — user-verified.**
- **CodexBar-style AI limits in the notch** (`scripts/ai/usage_poll.py` +
  `services/AiUsage.qml`): Codex = EXACT subscription percentages parsed from
  ~/.codex/sessions rollout jsonl rate_limits events; Claude = 5h-block estimate
  via npx ccusage (tokens vs largest completed block; JSON output never fills
  tokenLimitStatus — ceiling computed ourselves; 5-min cache, failures never
  cached — stale beats blank; between-blocks → 100% left). UI: idle-notch chips
  + "AI limits" strip in the System tab; saturated estimates render orange
  "at max*", not red "0% left".
- **Lockscreen concave shoulders** (`NotchShoulder.qml`): island's RoundCorner
  fillet ported (no qs deps), registered in the theme qmldir (dir has a qmldir →
  implicit same-dir types don't resolve). Shoulders ride the pill during morphs;
  lock/desktop notches are now shape-identical.

## Earlier: 
**PLASMA EDITION — feature-complete and user-verified (2026-07-09).** Everything
below is live, pushed to the Tolib-N8 fork, and confirmed working by the user:

- **Island-style kscreenlocker theme** (`plasma/lockscreen/` +
  `install-lockscreen.sh`): notch clock pill + password pill, with a **seamless
  notch handoff** — the lock pill starts/ends at the desktop notch's exact idle
  geometry (180×36, r18), so lock reads as the notch growing into the clock and
  unlock shrinks it back into the real desktop notch. A true QS locker is
  IMPOSSIBLE on KWin (no ext-session-lock-v1 in the registry — verified).
  Gotchas: KPackage rejects symlinks outside the package root, and a partial
  user shell-package breaks resolution entirely (would break plasmashell) — only
  a full real copy of org.kde.plasma.desktop works; re-run the install script
  after Plasma upgrades. Preview: `kscreenlocker_greet --testing`.
- **Notch = notification server** (swaync masked): native actions, click a
  notification (morph or dashboard panel row) → invoke its default action;
  newest-first panel; icons need `QT_QPA_PLATFORMTHEME=kde` (set in autostart).
- **Voice assistant overlay**: notch is the Code assistant's overlay (voice IPC:
  bars/idle/text/hide/level; `show` collides with `ipc show` — renamed `bars`);
  levels polled from /tmp/assistant_levels (onLoaded signal, NOT onLoadedChanged);
  assistant PTT rewritten pynput→evdev (Wayland), key = Right Ctrl (Fn is
  firmware-level, invisible to evdev).
- Meta+Q no longer closes the notch (no keyboard focus off-Hyprland); notif
  bridge legacy kept for reference but unwired.

**Earlier phase (2026-07-01):**
**PLASMA EDITION (Variant A: notch-only) — WORKING + VERIFIED on KDE Plasma
Wayland/KWin (2026-07-01).** A separate Quickshell config root at `plasma/`
renders only the central morphing notch + the agent bridge, to run alongside
Plasma's native panels. Verified live on this machine (KWin): notch renders as a
layer-shell surface, media morph + cava visualizer work, agent-status morph works,
and the Claude Code **permission round-trip works end-to-end** (card → click Allow
All → decision written back to the hook). Reuses the existing global hooks in
`~/.claude/settings.json` and the `$XDG_RUNTIME_DIR/openagentisland.sock` socket —
**no bridge/hook changes needed** (both are DE-agnostic).

- **Layout:** `plasma/shell.qml` is the only new source (notch-only entry). All
  shared code is symlinked from `quickshell/`, so `import qs.*` resolves and the
  Hyprland shell is untouched.
- **Only Hyprland-specific notch feature = jump-to-terminal.** Made DE-aware in
  `quickshell/modules/ii/island/AgentSurface.qml`: `onHyprland` runtime check;
  Hyprland path (`hl.dsp.focus`) unchanged, else foreign-toplevel `activate()`
  (KWin-supported), matching terminal by title keywords (no PID in the protocol).
- **Deploy:** `ln -sfn ~/Projects/openagentisland/plasma ~/.config/quickshell/openagentisland-plasma`
  then `qs -c openagentisland-plasma`. Autostart template + docs in `plasma/`.
- **Plasma trade-offs (harmless):** notifications owned by Plasma (notch notif
  morph quiet); GlobalShortcut unsupported on KWin (bind via KDE settings).
- **TODO:** real-hardware test of jump-to-terminal against a live `claude`
  terminal; optional multi-monitor pass on Plasma; user autostart opt-in.

---

## Previous phase & status

**FEATURE-COMPLETE; multi-monitor blanking FIXED + VERIFIED on the scaled built-in
monitor; now running LIVE on `openagentisland` (2026-06-06).** All features built +
polished + validated. The headline feature (live Claude Code agent + permission
Allow/Deny from the notch) is safety-proven (13/13, never hangs Claude). The
multi-monitor blanking bug (below) is root-caused + fixed, and the fix was
**verified live on `eDP-1` (scale 1.5)** — the exact monitor that blanked before
now renders wallpaper + all three islands + dock correctly.

**Live state right now:** OpenAgentIsland is the PERMANENT desktop — `variables.lua`
is `hl.env("qsConfig", "openagentisland")` (backup: `variables.lua.bak-preisland`),
so it loads on every boot/relogin. **hooks ENABLED**; socket listener up at
`$XDG_RUNTIME_DIR/openagentisland.sock`. **Still UNVERIFIED on real hardware:** the
rotated vertical monitor (`DP-3`, transform 1) and the full 3-monitor combo (all
testing so far was on `eDP-1` 1.5× only, user mobile) — the logical-anchor fix
should handle rotation, but confirm on reconnect. **Rollback if multi-monitor
misbehaves:** set `variables.lua` → `hl.env("qsConfig", "ii")` (or restore the
.bak) and relog; or live-revert with
`pkill -f "qs -c openagentisland"; hyprctl dispatch exec "qs -c ii"`.

Re-test / swap commands:
- Hot-swap to island: `pkill -f "qs -c ii"; setsid qs -c openagentisland </dev/null >/tmp/oai.log 2>&1 &`
  (NOTE: `hyprctl dispatch exec "qs -c openagentisland"` did NOT keep it alive this
   session — use `setsid` to detach it from the launching shell.)
- Revert to ii: `pkill -f "qs -c openagentisland"; hyprctl dispatch exec "qs -c ii"`
- Hooks: `python3 ~/Projects/openagentisland/bridge/install-hooks.py enable|disable|status`

### ✅ MULTI-MONITOR BLANKING — root cause found + fixed
**Symptom (Path A switch, 3 monitors):** only the main external monitor worked;
the laptop built-in and the vertical monitor went COMPLETELY BLANK (no wallpaper /
dock / islands), plus wrong sizing. Confirmed by photos + `monitors.lua`:
- `HDMI-A-1` 2560×1440 **scale 1.0, no transform** → logical == physical → **worked**.
- `eDP-1` 2880×1800 **scale 1.5** → logical 1920×1200 → **blank**.
- `DP-3` 1920×1080 **transform 1 (rotated)** → logical 1080×1920 → **blank**.

**Root cause:** `IslandNotch.qml` sized its PanelWindow with PHYSICAL pixels —
`implicitWidth: screen.width; implicitHeight: screen.height`. Layer-shell surfaces
use LOGICAL coords, so on any monitor with scale≠1 or a rotation the full-screen
Top-layer surface was oversized/mis-axed and **broke compositing for the whole
output** (everything on it went black, wallpaper included). The one scale-1.0,
unrotated monitor was the only one where physical==logical, so it alone rendered.
The notch was the SOLE violator — every other panel (Background, Dock, left/right
islands) is content-/edge-sized and survived; their disappearance on the dead
monitors was collateral from the broken output, not their own bug.

**Fix (commit `c94a7b9`):** anchor the notch window `top+left+right` (logical
full-width per monitor) + fixed `implicitHeight: maxHeight+60`; removed both
`screen.width/height`. `exclusiveZone` (40) still honored (anchored top + both
perpendicular edges). This matches the framework's `Background`/`Dock` pattern,
which is already proven on all 3 of the user's monitors under `ii`. Trade-off: the
outside-click-to-close catcher now covers the top ~460px instead of the full
screen (Esc / re-click the pill still close); fine since surfaces hang from the top.

**VERIFIED (2026-06-06):** live hot-swap on `eDP-1` (scale 1.5) — wallpaper +
all three islands + dock render correctly; no blanking. The scaled-monitor failure
mode is fixed. STILL TO VERIFY: rotated `DP-3` (transform 1) + the full 3-monitor
combo (only `eDP-1` connected during the test). If a secondary monitor's wallpaper
ever looks mis-scaled, that's a separate `Background` parallax tweak (also uses
`screen.width` in its zoom math) — but it renders fine under `ii`, so likely moot.

Toggle hooks for real Claude work (currently DISABLED):
  python3 ~/Projects/openagentisland/bridge/install-hooks.py enable|disable|status

---

## Done (newest first)

- **2026-06-07 — CRITICAL GOTCHA: real desktop is a LUA-config Hyprland.** The
  standard dispatch form `Hyprland.dispatch("focuswindow address:…")` /
  `"workspace N"` SILENTLY NO-OPS on the user's real desktop (verified live:
  workspace didn't change). It only works in the nested dev window (vanilla
  Hyprland) — which is why island workspace/window dispatches "worked" in dev but
  not live. The correct form is the LUA API: `hl.dsp.focus({window = "address:…"})`,
  `hl.dsp.focus({workspace = N})`, `hl.dsp.window.move({…})`, `hl.dsp.window.close({…})`
  (same forms the upstream end-4 OverviewWidget uses). ✅ FIXED everywhere: all
  island `Hyprland.dispatch` callers now use `hl.dsp.*` — `AgentSurface` (jump),
  `IslandWorkspaces` (scroll+click; relative e±1 computed as absolute from
  `activeWs`), `OverviewSurface` (workspace switch, window focus/move/close).
  `grep Hyprland.dispatch modules/ii/island/` → all hl.dsp. (`LauncherSearch`
  already used `hl.dsp.global`.) The end-4 `OverviewWidget` (old overview, not our
  island) already used hl.dsp. NOTE: verify on the real desktop — proven live that
  `hl.dsp.focus({workspace=N})` and `{window="address:…"}` work.

- **2026-06-07 — Session permission-mode shown + live-synced.** Hook reports
  `permission_mode`; a colored ModeChip on each session row / permission card shows
  Bypass / Auto-edit / Plan (live from the terminal, updates on Shift+Tab) and
  island-side Auto:<tool> / Bypass from notch Allow-All/Bypass. (A hook cannot SET
  the terminal's mode — the notch reflects/augments, can't flip it.) Verified the
  notch Allow-All auto-rule DOES work (next same-tool request auto-allowed, no UI).

- **2026-06-07 — Jump-to-terminal fixed (Lua dispatch + Warp disambiguation).**
  Was broken because it used the standard dispatch form (see gotcha above) and
  because Warp shares one PID across all its windows. Now uses `hl.dsp.focus` and,
  when multiple windows share a PID, picks the one whose title best matches the
  session prompt/summary.

- **2026-06-06 — Jump-to-terminal (the previously-skipped feature).** Each session
  row in the agent list has an `open_in_new` button → focuses the terminal running
  that Claude session (switches workspace if needed). Mechanism: `oai_hook.py` sends
  its process-ancestor PIDs (`ancestor_pids()`); the terminal is always an ancestor
  of `claude`, so `AgentService` stores them and `AgentSurface.findWindow()` matches
  a PID against `HyprlandData.windowList`, then `Hyprland.dispatch("focuswindow
  address:…")`. Verified the ancestor chain includes the real window pid. Caveat:
  single-process multi-window terminals (Warp) share one pid across windows, so it
  focuses *a* Warp window, not the exact tab; per-process terminals (foot/kitty/
  alacritty) are precise. Button hidden when no window matches.

- **2026-06-06 — Per-monitor open + full-screen close-catcher + clean agent surface
  + restored top-strip reservation.** (3 reported bugs.) Island bus tracks
  `openScreen` so a surface opens only on the clicked monitor; notch window anchors
  all-4 (logical full-screen, multi-monitor safe) for a click-anywhere-to-close
  catcher; a separate stable strip window re-reserves the top 40px so windows sit
  below the islands; agent surface re-laid-out (title=project, prompt up to 2 lines,
  command = dimmed monospace tail).

- **2026-06-06 — Ghost sessions fixed via `SessionEnd` hook.** Closing a Claude
  session left a ghost row (`idle`/`waiting`) until the 5-min staleness timer,
  because `Stop` = "turn finished", not "session closed". Added Claude Code's
  `SessionEnd` hook (`install-hooks.py` STATUS_EVENTS) → `AgentService.endSession()`
  removes the session immediately (+ clears its pending rows & bypass rule).
  Verified: injection test (SessionStart→Notification/waiting→SessionEnd→removed)
  and a real `claude -p` one-shot leaving no ghost. Caveat: a hard kill (SIGKILL /
  crash) won't fire `SessionEnd` — the 5-min staleness backstop still cleans those.

- **2026-06-06 — Multi-monitor blanking ROOT-CAUSED, FIXED, and VERIFIED live.**
  Root cause: `IslandNotch.qml` sized its PanelWindow in PHYSICAL pixels
  (`implicitWidth/Height: screen.width/height`); layer-shell uses LOGICAL coords,
  so any monitor with scale≠1 or rotation got an oversized/mis-axed full-screen
  Top-layer surface that broke compositing for the whole output → blank. Confirmed
  with `monitors.lua` + photos: `HDMI-A-1` (1.0, no transform) worked; `eDP-1`
  (1.5×) + `DP-3` (transform 1) blanked. Fix (`c94a7b9`): edge-anchor the notch
  window `top+left+right` + fixed height, drop `screen.width/height`; matches the
  framework's `Background`/`Dock` sizing. Verified by hot-swapping the real desktop
  to `openagentisland` on the `eDP-1` 1.5× built-in — wallpaper, all 3 islands, and
  the dock render correctly (previously fully blank). Re-enabled hooks; agent
  feature ready to test live. Pending: rotated `DP-3` + full 3-monitor verification
  (user was mobile, single screen connected).

- **2026-06-06 — Phase 6+7 agent feature VALIDATED end-to-end (real Claude Code).**
  Ran a real `claude` session in `~/agent-island-test/` (project-level hooks,
  isolated from the dev session): notch showed SessionStart → Working… → the
  orange permission card with the real Write preview; approved from the island;
  Claude Code wrote hello.txt and continued. Full UI built + user-approved:
  AgentSpinner (4-frame running pixel mascot, state-tinted), AgentStatusText
  (shimmer + cycling dots, fixed width), compact State 2 (DI spread, fixed 224w,
  auto-collapse via 5s done-prune), AgentSurface State 3 (session list +
  permission card with write/edit/bash preview + Deny/Allow Once/Allow All/Bypass
  w/ 2-click confirm). Permission auto-opens the surface and auto-closes on
  resolve. Bugs fixed live: status string mismatch (running vs working), stale
  "permission" status after resolve/timeout (dropPending reverts to working).

- **2026-06-05 — Phase 6 agent bridge BACKEND (safety-first).** Built the riskiest
  piece first and proved it before any UI. `bridge/oai_hook.py` (Python — no
  socat/nc on this box) forwards Claude Code hook events to a unix socket; for
  PreToolUse it blocks for an Allow/Deny decision with a hard timeout. **Safety
  contract:** any failure (no socket / refused / timeout / frozen / exception) →
  exit 0, no stdout → Claude falls back to its normal prompt; never hangs, never
  auto-approves. `bridge/test_safety.py` proves it (13/13: down, allow, deny,
  frozen→bounded fallback, delivery). Quickshell side `services/AgentService.qml`
  hosts a `SocketServer`, keeps per-session status + a pending-permission queue,
  writes decisions back on the held connection, and drops a pending request if
  its connection closes (queue can't wedge). Verified END-TO-END through the real
  Quickshell listener: status events received with correct project/tool/summary;
  full allow + deny round-trip via the `agent` IPC target; disconnect cleanup.
  Gotchas: Quickshell `SocketServer.handler` is a `QQmlComponent` (one `Socket`
  per connection); `Socket` has `write()`/`flush()`/`connected`; new singleton
  needed a fresh `qs` start to register (imported-module quirk) — socket appeared
  after restart. Hooks documented but NOT yet wired into live `~/.claude/`.

- **2026-06-05 — Expansion phases A–H (notch surfaces + side islands).** Built the
  whole reference feature set ahead of the agent work; each phase compiled clean
  (verified via reload log + force-opening each surface) and committed separately
  (commits Phase A `45c8fe8` → Phase H). New files under `modules/ii/island/`:
  `Island` (bus singleton), `DashboardSurface`/`DashboardPlaceholder`,
  `WidgetsPane`/`WidgetCalendar`, `KanbanStore`/`KanbanPane`, `PowerSurface`,
  `ToolsSurface`, `LauncherSurface`, `OverviewSurface`, `IslandWeatherPill`,
  `IslandNetworkPill`. `IslandNotch` open state → Loader surface-host; `IslandLeft`
  rebuilt to 5 pills (title dropped); `IslandRight` gained pencil pill + power→surface.
  Gotchas hit:
  - **New-file reload race:** adding a new surface file + editing IslandNotch to
    reference it in the SAME reload nudge yields a transient `X is not a type`
    "Failed to load" pass, immediately followed by a successful "Configuration
    Loaded". The `Component { X {} }` wrapper forces X to be a valid type for the
    config to load at all, so a trailing `Configuration Loaded` proves it resolved
    — trust the LAST line; the interleaved error is stale (its line:col often no
    longer even points at the Component after later edits).
  - **PowerProfilesDaemon not running** on this box → mode selector shows default
    and `powerprofilesctl set` is a harmless no-op (env, not a bug).
  - **end-4 `hl.dsp.*` dispatchers are plugin-only** (invalid in vanilla Hyprland)
    — OverviewSurface uses standard `focuswindow`/`closewindow`/
    `movetoworkspacesilent`/`workspace` instead.
  - **Cross-cell/column drag** (kanban + overview): avoided Repeater-delegate
    reparenting; instead arm after 8px, show a floating proxy, and on release map
    cursor position → target cell/column. Robust without z-order fighting.

- **2026-06-05 — Phase 5 media + cava visualizer (notch).**
  - One shared cava `Process` at the `Scope` root runs `cava -p scripts/cava/
    raw_output_config.txt` (50 bars, `;`-sep stdout) only while `mediaActive` →
    `visualizerPoints`. Downsampled to 22 **equalizer bars** (center-anchored
    Rectangles) — NOT the `WaveVisualizer` (user wanted bars).
  - Minimal media UI (reference-style): small album art · bars · play/pause. NO
    title/artist. Compact (~40px). `MprisController.activePlayer`.
  - `mediaActive = isPlaying` → pausing/no-playback collapses back to idle (user choice).
  - **Album-art flicker fix:** binding straight to `trackArtUrl` made art vanish when the
    player rewrote/cleared the URL. Fix = download to a stable local cache
    (`Directories.coverArt/Qt.md5(url)` via a curl `Process`) AND only clear `displayedArt`
    on an actual track change (`trackKey`=trackTitle), set only on curl exit 0. Persists.
- **2026-06-04 — Phase 4 notch brightness + notification.** Generalized to one
  `expandedSource` + shared hide-timer; reusable `OsdBar`/`OsdPercent`. NOTE: brightness
  only fires when changed THROUGH the shell service (`Brightness.brightnessChanged`;
  test via `qs -c openagentisland ipc call brightness increment`), and notifications
  CANNOT be tested in the nested session — the real `ii` already owns the
  `org.freedesktop.Notifications` D-Bus name, so the nested shell gets none. Both wired
  correctly; verify on real desktop.
- **2026-06-04 — Phase 3 notch idle + volume + the morphing framework.**
  - Top-attached notch: square top corners flush with screen edge, rounded bottom,
    concave `RoundCorner` shoulders (left=TopRight, right=TopLeft, overlap −1px) blending
    into the top edge. Borderless (a border drew seam lines). Window fixed at max size +
    `mask: Region{item:notch}` (click-through elsewhere) so size animates smoothly
    Qt-side (no janky per-frame compositor resize).
  - Goey morph: `easing.bezierCurve` from the reference's notch.css
    (`cubic-bezier(0.175,0.885,0.32,1.275)`), softened to **[0.34,1.22,0.64,1,1,1]**
    (1.275 made the open→idle shrink collapse violently; user still wanted bounce).
  - **Constant 18px bottom radius** (≤ idle-height/2 so Qt never clamps it) — animating
    the radius read as corners "rounding in", which the user rejected. idle height = 36.
  - Volume triggers off `Audio.sink.audio` VALUE (not `GlobalStates.osdVolumeOpen`).

- **2026-06-04 — Phase 2 RIGHT island + sidebar slide-in.**
  - `IslandRight.qml`: pills = stats (CPU/RAM/SWAP/battery as `CircularProgress` rings,
    hover → combined RAM/Swap/CPU/Battery tooltip) · tray (hidden when empty) ·
    perf-toggle + settings-gear · clock (12h `h:mm AP`, small) · circular power button.
    Smooth `Behavior on color` hovers on gear/perf/power.
  - `IslandPopup.qml` (new): hover tooltip anchored BELOW via `PopupWindow` (the bar's
    `StyledPopup` is hard-coded for the full-width bar → lands top-left on our island).
    Loader-based + keep-alive timer = crash-safe (an always-mapped PopupWindow triggered
    a Wayland popup protocol error → killed qs). Content passed as a `Component`
    (instantiated fresh inside; reparenting a shared Item rendered empty boxes). Slides
    in from the right + fades, both ways.
  - `IslandWorkspaces.qml`: fixed dispatch — end-4's `hl.dsp.focus({...})` is invalid in
    vanilla Hyprland ("Invalid dispatcher"); switched to standard `workspace N` / `e±1`.
  - `SidebarRight.qml`: top margin 44 (opens below the island strip) + slides in from the
    right screen edge (Translate on content, window kept mapped through slide-out).
  - Gotchas: brace-balance bugs are easy to misdiagnose because `${}` template literals
    and reload-race stale reads show contradictory errors — verify with a string/comment/
    template-aware brace counter, not `grep -c {`.

- **2026-06-03 — Phase 2 LEFT island.** Built the left island iteratively with the user:
  - `IslandWorkspaces.qml` (custom): a `Row` of uniform-spaced dots where the CURRENT
    workspace is a capsule (same height as dots) that **expands and pushes neighbours**
    apart → genuinely uniform gaps + fluid 280ms animation. Reuses end-4's Hyprland
    dispatch (`hl.dsp.focus`) + occupancy logic. Used dots = white, unused = faint,
    current = blue-tint. Scroll = switch ws, right-click = overview, left-click = focus.
    (Earlier tried bending the reused end-4 `Workspaces.qml` via override props, but
    fixed slots can't give uniform spacing around an elongated capsule — reverted that
    file to pristine and went custom.)
  - `ActiveWindow.qml`: added `compact` mode (single-line title, short "Desktop" idle
    label) — default off, so the disabled bar is unaffected.
  - `IslandStyle.qml` (singleton): shared tokens — solid space-black `#0B0B0E` pill,
    white text, `#8AB4F8` blue accent, 4px edge margin, 32px height, full radius. ALL
    islands use this for consistency.
  - Left-click pill → `sidebarLeftOpen`. Verified by user across several rounds of
    color/spacing/size tuning.

- **2026-06-03 — Phase 0 orientation.**
  - Read `~/Projects/island-reference/hyprfabricated/modules/notch.py` (995 lines) and
    `utils/animator.py`. Key finding: their notch "morph" is a GTK `Stack` with
    `set_interpolate_size(True)` swapping fixed-size children, NOT a width/height tween;
    the functional left/right clusters live in a separate full-width bar (we split those
    into two floating islands); single-window, no multi-monitor. animator.py is a
    hand-rolled cubic-bezier tick tween → replaced by native Qt `Behavior`/`easing`.
  - Wrote `NOTES.md` and `PROGRESS.md`.
  - **Surveyed current repo state:**
    - `panelFamilies/IllogicalImpulseFamily.qml`: full-width `Bar` PanelLoader ACTIVE;
      `// PanelLoader { component: Island {} }` commented out; `qs.modules.ii.island`
      already imported.
    - `modules/ii/island/` already contains a **prior-session sketch**:
      `Island.qml` (static 220×32 "island" pill, single `PanelWindow` in `Variants`,
      anchored top-center) and `IslandContent.qml` (volume-only state machine where
      `idle` is *invisible* and the trigger is `GlobalStates.osdVolumeOpen`). Both
      diverge from the target design (idle should be a minimal clock; trigger off the
      `Audio` value, not the flickering flag). Treat as a sketch to rewrite in Phase 3.
  - **Dev env confirmed present:**
    - Runtime symlink OK: `~/.config/quickshell/openagentisland` →
      `~/Projects/openagentisland/quickshell`.
    - Nested Hyprland config OK: `~/.config/hypr-nested/hyprland.conf`
      (monitor `WL-1 2560x1440@60`, `exec-once = qs -c openagentisland`,
      animations/blur disabled).
    - The live `ii` config is untouched (hard rule).

---

## Next

1. **Notch `open` (fully-expanded) state content** — the `open` state (click-toggled,
   480×300) currently has the shape/morph but NO content. Design + build what it shows
   (likely the agent view + media controls + a dashboard-ish surface). User wants to
   iterate on the expanded/open notch.
2. **Phase 6 — agent bridge (status only), safety-first.** Build `bridge/` (NOT created
   yet): Unix socket at `$XDG_RUNTIME_DIR/openagentisland.sock`, Claude Code hooks →
   socket, a listener → notch `agent` state. Build the timeout/failure-safety FIRST so a
   down/broken island can NEVER hang real Claude Code. Confirm `Quickshell.Io` 0.2.1
   socket support (or external daemon). See NOTES.md §4.
3. Phase 7 permission round-trip, Phase 8 multi-session + polish.

Dev: launch nested window with
`WLR_BACKENDS=wayland WLR_NO_HARDWARE_CURSORS=1 HYPRLAND_INSTANCE_SIGNATURE= Hyprland --config ~/.config/hypr-nested/hyprland.conf`

---

## Blockers / open questions

- (Phase 6) Confirm `Quickshell.Io` 0.2.1 supports a listening socket +
  bidirectional/blocking writes from QML; if awkward, propose an external listener
  daemon to the user before building.
- Memory file `project_openagentland.md` describes this as a "fork of dynisland" —
  that is **stale/incorrect**; the actual project is Quickshell/QML on end-4 per
  `CLAUDE.md`. Trusting `CLAUDE.md` + the repo.

---

## Gotchas hit

- **⚠ NESTED MONITOR NAME VARIES PER SESSION → broke scaling.** The nested output is
  sometimes `WL-1`, sometimes `WAYLAND-1` (changes after a laptop reboot). A
  `monitor=WL-1,...` line silently stops matching → nested falls back to scale 1.5 +
  letterboxed wallpaper. FIX (in `~/.config/hypr-nested/hyprland.conf`): use a wildcard
  `monitor=,preferred,auto,1.0` (empty name = all outputs). Monitor changes need a
  nested-session restart. Check actual name/scale with
  `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl monitors` (find the nested instance under
  `$XDG_RUNTIME_DIR/hypr/`).
- **ConflictKiller "Kill conflicting programs? kded6" dialog** appears in the nested
  session (`ConflictKiller.load()` in shell.qml). Click **No** — `kded6` is shared with
  the real desktop; killing it would break the real session's KDE integration.
- **Brace-balance is easy to misdiagnose:** `${...}` template literals contain `{`/`}`,
  so `grep -c '{'` lies. Use a string/comment/template-aware counter (a small python
  walker). Also, the reload race shows CONTRADICTORY stale errors ("Expected }" then
  "Unexpected }") from different in-flight file states — trust the LAST
  `Configuration Loaded` line, not transient errors.
- **`exclusiveZone` for "windows below the islands":** set
  `exclusionMode: ExclusionMode.Normal; exclusiveZone: 40` on the (top-anchored) notch
  to reserve the top strip so maximized windows don't get covered. Wallpaper (Background,
  layer Bottom, `ExclusionMode.Ignore`) still fills the whole screen.
- **Notifications can't be tested in the nested session** (real `ii` owns the D-Bus
  notification server). **Brightness** only triggers when changed through the shell
  service. Verify both on the real desktop. **Volume/media ARE testable** (shared
  PipeWire / MPRIS).
- **WaveVisualizer / any self-anchoring widget inside a Layout** → "anchors on an item
  managed by a layout" warning; wrap it in a plain `Item` with `Layout.preferredWidth/
  Height` and let the widget `anchors.fill: parent`.

- **⚠ HOT-RELOAD DOESN'T FIRE FROM CLAUDE'S FILE WRITES (critical, every phase).**
  Claude's Write/Edit tools save *atomically* (write temp + rename → new inode), and
  Quickshell's file watcher is on the old inode, so it never sees the change. Symptom:
  you edit a `.qml`, nothing updates in the nested window, and there's NO red error
  panel (suppressed by `//@ pragma Env QS_NO_RELOAD_POPUP=1` in `shell.qml`). Diagnosed
  via `qs -c openagentisland log` (shows "Configuration Loaded" only at launch, no
  reload). Also: a **plain `touch` does NOT reload** (mtime/IN_ATTRIB ignored); only a
  real content change (IN_MODIFY) does, and it must *persist* (append+immediate-truncate
  nets zero and gets coalesced → no reload).
  **Reliable reload nudge after editing QML** (in-place, then restore so git stays clean):
  ```bash
  bash -c "printf '%s\n' '// reload-nudge' >> ~/Projects/openagentisland/quickshell/shell.qml"
  sleep 2   # let Quickshell reload from current disk state
  cd ~/Projects/openagentisland/quickshell && git checkout shell.qml   # remove the nudge line
  ```
  When the **user** saves from their own editor, normal hot-reload works fine — this
  only affects Claude's tool-writes. `qs -c openagentisland log` is the way to read
  silenced QML errors (note the log/"Configuration Loaded" counter appears capped, so
  trust the screenshot + error lines, not the reload count).
- User shell is **fish** — no `<<EOF` heredocs; write files with tools or
  `printf`/`cat` inside `bash -c '...'`. (A chained `ls A B && find …` failed because
  fish/`ls` returned exit 2 when one path was missing and short-circuited the `&&`.)
- A prior session already scaffolded `modules/ii/island/` — check existing files before
  creating, to avoid clobbering or duplicating.
