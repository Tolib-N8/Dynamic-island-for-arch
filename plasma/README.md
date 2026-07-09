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

## Notifications (the notch IS the server)
The notch's built-in `Notifications` service owns `org.freedesktop.Notifications`
directly, so notifications arrive natively — with **actions**: clicking a
notification in the notch invokes its default action (open the app / follow the
notification) via `Notifications.attemptInvokeAction`. No popup duplication, no
mirror bridge, no Do-Not-Disturb.

For this the previous daemon (**SwayNotificationCenter**) must not hold the name.
swaync is a D-Bus-activated systemd unit (`BusName=org.freedesktop.Notifications`,
`Restart=on-failure`), so stopping it isn't enough — it must be **masked**:

```sh
systemctl --user mask swaync.service   # reversible: `unmask`
systemctl --user stop swaync.service
pkill -x swaync
```

Then the running notch grabs the name (it retries whenever the name frees).
Trade-off: the notch becomes the *only* notification server, so **notifications
are lost while the notch isn't running** (there's no fallback daemon). The
autostart entry starts it on login; if you want swaync back, `unmask` + start it
and revert the notch to a passive mirror.

(An earlier mirror approach — `bridge/notif_bridge.py` snooping D-Bus + swaync in
DND — is kept in the repo for reference but no longer wired in `plasma/shell.qml`.)

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

## Island-style lock screen (kscreenlocker theme)
A true Quickshell locker is impossible on KWin (no `ext-session-lock-v1`), so the
island look is brought to **kscreenlocker itself**: `plasma/lockscreen/` is a
restyled copy of the stock Plasma 6 lock screen — a black notch-shaped clock pill
top-center (rounded bottom corners, white time + grey date, exactly like the idle
island) and the password row wrapped in a dark rounded pill. All stock behavior
(PAM auth, fingerprint, media controls, Sleep/Switch User, virtual keyboard)
is untouched.

Install / refresh (also re-run after Plasma upgrades):
```sh
plasma/install-lockscreen.sh              # install
plasma/install-lockscreen.sh uninstall    # restore stock
/usr/lib/kscreenlocker_greet --testing    # preview without locking
```
The script copies the whole `org.kde.plasma.desktop` shell package to
`~/.local/share/plasma/shells/` and overlays the theme — KPackage canonicalizes
paths and rejects symlinks out of the package root, and a partial user copy
breaks package resolution entirely, so a full real copy is the only safe layout.
If the theme ever fails to load, kscreenlocker falls back to its built-in locker
(you can always unlock).

## Known trade-offs on Plasma
- **GlobalShortcut**: uses `hyprland_global_shortcuts_v1`, unsupported on KWin —
  bind any shortcuts through KDE System Settings instead. (Harmless warning.)
- **jump-to-terminal** is best-effort (title match) since foreign-toplevel exposes
  no PID. Works best when the terminal title reflects the Claude session.
