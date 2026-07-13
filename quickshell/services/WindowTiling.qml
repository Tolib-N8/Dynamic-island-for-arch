pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Auto-tile toggle (Hyprland only). ON — new windows tile as usual and get
 * auto-sized by the layout. OFF — every new window is floated immediately, so
 * it keeps its own size. Floating happens per-window on the openwindow event;
 * NOTE this Hyprland build routes ALL dispatch strings through its Lua config
 * plugin, so the dispatcher must be written as an hl.dsp.* Lua expression —
 * plain `setfloating address:...` is rejected.
 */
Singleton {
    id: root

    // true = tiling (auto-size), false = new windows open floating
    property bool autoTile: true

    Connections {
        target: Hyprland
        enabled: !root.autoTile
        function onRawEvent(event) {
            if (event.name !== "openwindow")
                return;
            const addr = event.data.split(",")[0];
            if (addr.length === 0)
                return;
            Quickshell.execDetached(["hyprctl", "dispatch",
                `hl.dsp.window.float({ action = "on", window = "address:0x${addr}" })`]);
        }
    }

    IpcHandler {
        target: "tiling"

        function toggle(): void { root.autoTile = !root.autoTile; }
        function on(): void { root.autoTile = true; }
        function off(): void { root.autoTile = false; }
        function dump(): string { return root.autoTile ? "tiling" : "floating"; }
    }
}
