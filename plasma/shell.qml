//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// OpenAgentIsland — Plasma edition (Variant A).
//
// A stripped entry point that renders ONLY the central morphing notch + the
// Claude Code agent bridge, meant to run as its own Quickshell instance
// alongside KDE Plasma's own panels. No side islands, no Bar, no workspaces —
// those are Hyprland-specific and live in the full Hyprland shell (shell.qml
// in ../quickshell). The notch itself is compositor-agnostic: it renders as a
// wlr-layer-shell surface, which KWin (Plasma Wayland) supports.
//
// Shared modules/services are symlinked into this config root so `import qs.*`
// resolves here exactly as in the Hyprland shell.

import "modules/common"
import "services"

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.ii.island

ShellRoot {
    id: root

    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()   // pick up generated Material colors
        AgentService.load()                  // start the Claude Code agent bridge listener
        NotificationMirror.socketPath        // force-instantiate → its socket server starts
    }

    // Mirror the desktop's notifications into the notch, and put the real daemon in
    // Do-Not-Disturb so the notch is the only popup. Run as a managed Process (not
    // execDetached) so it's tied to the notch's lifetime: if the notch stops, the
    // bridge is terminated → it restores the daemon's popups on the way out.
    Process {
        id: notifBridge
        running: true
        command: ["python3", Quickshell.env("HOME") + "/Projects/openagentisland/bridge/notif_bridge.py"]
        // Auto-respawn if it ever dies, so notifications (and DND restore) never
        // get stuck. Small delay avoids a tight crash loop.
        onExited: respawn.start()
    }
    Timer { id: respawn; interval: 1500; onTriggered: notifBridge.running = true }

    // The star, and only the star.
    LazyLoader {
        active: Config.ready
        component: IslandNotch {}
    }

    // On Plasma there are no side islands to trigger surfaces, and KWin doesn't
    // speak hyprland_global_shortcuts. So expose the notch over IPC — bind a KDE
    // custom shortcut to e.g. `qs -c openagentisland-plasma ipc call island dashboard`.
    IpcHandler {
        target: "island"

        function _screen(): string {
            return Quickshell.screens.length > 0 ? (Quickshell.screens[0].name ?? "") : "";
        }
        function dashboard(): void { Island.toggle("dashboard", _screen()); }
        function agent(): void { Island.toggle("agent", _screen()); }
        function close(): void { Island.close(); }
    }

    // The "Code" voice assistant drives the notch as its overlay (replacing its
    // own quickshell overlay.qml). See ai-assistant/scripts/common.py.
    IpcHandler {
        target: "voice"

        function bars(): void { VoiceAssistant.mode = "bars"; }              // live mic bars ("show" collides with the `ipc show` subcommand)
        function idle(): void { VoiceAssistant.mode = "idle"; }              // gentle idle animation
        function hide(): void { VoiceAssistant.mode = "hidden"; VoiceAssistant.text = ""; VoiceAssistant.level = 0; }
        function text(msg: string): void { VoiceAssistant.text = msg; VoiceAssistant.mode = "text"; }
        function level(rms: real): void { VoiceAssistant.level = Math.max(0, Math.min(1, rms)); }
        function dump(): string { return VoiceAssistant.mode + " active=" + VoiceAssistant.active + " level=" + VoiceAssistant.level; }
    }
}
