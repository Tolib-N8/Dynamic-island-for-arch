pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Auto-tile toggle (Hyprland only). ON — windows tile and the layout sizes
 * them. OFF — a runtime window rule floats every window AT MAP TIME, so it is
 * born floating at its client-requested size. (Reacting to the `openwindow`
 * event instead let the window flash tiled/full-size for ~0.5s before popping
 * out — what this replaces.)
 *
 * Hyprland specifics on this Lua-config build (all verified empirically):
 *  - `hyprctl keyword` is rejected ("non-legacy parser"); runtime rules go in
 *    through `hyprctl eval` as Lua: hl.window_rule{...}.
 *  - A `window.open_early` hook that floats the window (property or dispatch)
 *    reports success but does NOT stick — the rule is the only thing that does.
 *  - Runtime rules cannot be removed: no removal API, and GC doesn't drop them.
 *    `hyprctl reload` rebuilds the Lua state and is the only way out. It is
 *    safe: every exec sits in the `hyprland.start` block, which does not
 *    re-fire on reload (measured: process counts unchanged).
 */
Singleton {
    id: root

    // true = tiling (auto-size), false = new windows are born floating
    property bool autoTile: true
    property bool _syncing: false

    onAutoTileChanged: {
        if (root._syncing)
            return;
        if (root.autoTile) {
            Quickshell.execDetached(["hyprctl", "reload"]);   // drops the rule
        } else {
            // Guarded so repeated toggles never stack duplicate rules.
            Quickshell.execDetached(["hyprctl", "eval",
                "if not OAI_FLOAT_RULE then OAI_FLOAT_RULE = hl.window_rule({match={class=\".*\"}, float=true}) end"]);
        }
    }

    // On (re)start, adopt the compositor's actual state so a quickshell restart
    // doesn't desync the chip from a rule that is still installed.
    Process {
        running: true
        command: ["bash", "-c",
            "hyprctl eval 'local f=io.open(\"/tmp/oai-float-rule\",\"w\") f:write(tostring(OAI_FLOAT_RULE ~= nil)) f:close()' >/dev/null 2>&1; sleep 0.2; cat /tmp/oai-float-rule 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "true") {
                    root._syncing = true;
                    root.autoTile = false;
                    root._syncing = false;
                }
            }
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
