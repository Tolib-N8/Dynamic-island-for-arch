# OpenAgentIsland — Plasma edition (Variant A: notch-only)

A stripped Quickshell config that renders **only the central morphing notch + the
Claude Code agent bridge**, made to run **alongside KDE Plasma's own panels** on
Plasma Wayland (KWin). No side islands, no Bar, no workspaces — those are
Hyprland-specific and stay in the full Hyprland shell (`../quickshell`).

## Why this works
- The notch is a **wlr-layer-shell** surface. KWin supports layer-shell, so
  Quickshell renders the notch on Plasma unchanged.
- The agent bridge (`../bridge/oai_hook.py`) is **compositor-agnostic** — it just
  talks to a Unix socket at `$XDG_RUNTIME_DIR/openagentisland.sock`. The same
  globally-installed Claude Code hooks in `~/.claude/settings.json` drive both the
  Hyprland shell and this Plasma edition. **No hook changes needed.**

## Layout
This directory is its own Quickshell **config root**. Shared code is symlinked
from `../quickshell` so `import qs.*` resolves here identically to the Hyprland
shell:

```
plasma/
├── shell.qml          # NEW — notch-only entry point (the only real file)
├── services  -> ../quickshell/services
├── modules   -> ../quickshell/modules
├── assets    -> ../quickshell/assets
├── scripts   -> ../quickshell/scripts
├── translations -> ../quickshell/translations
├── defaults  -> ../quickshell/defaults
├── GlobalStates.qml -> ../quickshell/GlobalStates.qml
└── ReloadPopup.qml  -> ../quickshell/ReloadPopup.qml
```

Because the modules tree is shared, the only Hyprland-specific behavior in the
notch path — **jump-to-terminal** — is handled by a runtime check in
`modules/ii/island/AgentSurface.qml`: on Hyprland it uses `hl.dsp.focus` (byte-for-byte
unchanged); off Hyprland it falls back to the wlr-foreign-toplevel protocol
(`Toplevel.activate()`), matching the terminal by window-title keywords.

## Install / run
```sh
# deploy as its own Quickshell config
ln -sfn ~/Projects/openagentisland/plasma ~/.config/quickshell/openagentisland-plasma

# run (foreground, for testing)
qs -c openagentisland-plasma

# run detached
setsid qs -c openagentisland-plasma </dev/null >/tmp/oai-plasma.log 2>&1 &
```

## Autostart on Plasma login
Copy the provided desktop entry into your autostart dir:
```sh
cp ~/Projects/openagentisland/plasma/openagentisland-plasma.desktop ~/.config/autostart/
```
(Or add it via System Settings → Autostart → Add Application → the same command.)

## Opening the notch (IPC + KDE shortcuts)
On the Hyprland shell the side islands trigger the notch surfaces; the Plasma
edition has no side islands and KWin doesn't speak `hyprland_global_shortcuts`, so
the notch is driven over Quickshell IPC instead:

```sh
qs -c openagentisland-plasma ipc call island dashboard   # toggle the dashboard
qs -c openagentisland-plasma ipc call island agent       # toggle the agent surface
qs -c openagentisland-plasma ipc call island close       # close
```

Bind these in **System Settings → Shortcuts → Custom Shortcuts** to get a hotkey
for the notch (e.g. Meta+/ → dashboard). The dashboard has three tabs:
**Widgets · Kanban · System** — the *System* tab (CPU / memory / swap / battery +
host info) is a Plasma-edition addition that replaces the resources the side
islands used to show.

## Notifications (mirrored — the notch is the only popup)
Another daemon owns `org.freedesktop.Notifications` (here it's
**SwayNotificationCenter**), so the notch can't be the server itself. Instead of
fighting for the name, `bridge/notif_bridge.py` becomes a passive D-Bus
**monitor**: it watches every `Notify` call and forwards a compact line to the
notch over `$XDG_RUNTIME_DIR/openagentisland-notif.sock`. The `NotificationMirror`
service holds the list; the dashboard Notifications panel and the notch's
notification morph render from it. On Hyprland this stays empty (the built-in
server is used there), so it's harmless in both shells.

To avoid double popups (daemon + notch), while the bridge runs it puts the daemon
in **Do-Not-Disturb** (`swaync-client -dn`) so only the notch pops — the daemon
still records history, and notifications still traverse D-Bus so the mirror keeps
working. This is **tied to the notch's lifetime**: the bridge runs as a managed
`Process` in `plasma/shell.qml`, so if the notch stops, the bridge is terminated
and **restores the daemon's popups on the way out** (`swaync-client -df`).

No hooks, no config. Flags for `notif_bridge.py`: `--print` (debug, don't
forward), `--no-suppress` (leave the daemon's popups on), `--inhibit` (try the
standard FDO Inhibit on daemons that support it, e.g. GNOME).

## Voice assistant overlay (Code)
The notch doubles as the overlay for the **"Code" voice assistant**
(`/mnt/steam/Projects/ai-assistant`), replacing its standalone quickshell
`overlay.qml`. The `VoiceAssistant` service holds the state and the notch morphs
into a bars/idle/text "assistant" surface (top precedence). Driven over the
`voice` IPC:

```sh
qs -c openagentisland-plasma ipc call voice bars     # live mic bars (was "show")
qs -c openagentisland-plasma ipc call voice idle     # gentle idle animation
qs -c openagentisland-plasma ipc call voice text "Открываю браузер"
qs -c openagentisland-plasma ipc call voice hide
qs -c openagentisland-plasma ipc call voice dump     # debug: mode/active/level
```

Live audio levels come through `/tmp/assistant_levels` (the assistant already
writes it), polled by `VoiceAssistant` — no IPC per audio frame. The assistant
side lives in `ai-assistant/scripts/common.py` (`overlay_cmd`/`overlay_start`/
`overlay_stop`/`write_level` now target this IPC; config name overridable via
`NOTCH_QS_CONFIG`). Note: `voice bars` is named `bars` not `show` because `show`
collides with quickshell's `ipc show` subcommand.

## Icon theme (notification icons)
Notification cards resolve their icon via the Qt icon theme. Quickshell only picks
up the KDE icon theme (from `kdeglobals`) when it loads the KDE platform theme
plugin, so the notch must be started with **`QT_QPA_PLATFORMTHEME=kde`** —
otherwise theme icons (e.g. the USB "device detected" icon) render as a magenta
"missing icon" square. The autostart `.desktop` sets this (`env
QT_QPA_PLATFORMTHEME=kde qs …`); launch it the same way if starting by hand.

## Known trade-offs on Plasma
- **GlobalShortcut**: uses `hyprland_global_shortcuts_v1`, unsupported on KWin —
  bind any shortcuts through KDE System Settings instead. (Harmless warning.)
- **jump-to-terminal** is best-effort (title match) since foreign-toplevel exposes
  no PID. Works best when the terminal title reflects the Claude session.
