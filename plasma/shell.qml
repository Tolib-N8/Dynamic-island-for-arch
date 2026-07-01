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

import qs.modules.common
import qs.modules.ii.island

ShellRoot {
    id: root

    ReloadPopup {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()   // pick up generated Material colors
        AgentService.load()                  // start the Claude Code agent bridge listener
    }

    // The star, and only the star.
    LazyLoader {
        active: Config.ready
        component: IslandNotch {}
    }
}
