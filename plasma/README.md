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

## Notifications (mirrored, non-invasive)
Plasma's `plasmashell` owns the `org.freedesktop.Notifications` D-Bus server, so
the notch can't be the server itself. Instead of fighting for it (which would
disable KDE's native notifications), `bridge/notif_bridge.py` becomes a passive
D-Bus **monitor**, watches every `Notify` call, and forwards a compact line to
the notch over `$XDG_RUNTIME_DIR/openagentisland-notif.sock`. KDE keeps showing
its own popups; the notch mirrors them (dashboard Notifications panel + the
notification morph). The `NotificationMirror` service holds the list; on Hyprland
it stays empty (the built-in server is used there), so it's harmless in both shells.

The bridge is launched automatically by `plasma/shell.qml` on startup
(single-instance, fire-and-forget). No hooks, no config. To run it by hand:
`python3 ~/Projects/openagentisland/bridge/notif_bridge.py` (`--print` to debug).

## Known trade-offs on Plasma
- **GlobalShortcut**: uses `hyprland_global_shortcuts_v1`, unsupported on KWin —
  bind any shortcuts through KDE System Settings instead. (Harmless warning.)
- **jump-to-terminal** is best-effort (title match) since foreign-toplevel exposes
  no PID. Works best when the terminal title reflects the Claude session.
