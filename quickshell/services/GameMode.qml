pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Game Mode: one switch that strips the eye candy for maximum frames.
 * ON  — kill blur, shadows and all Hyprland animations (incl. the breathing
 *       border), switch power profile to performance, hold Caffeine.
 * OFF — `hyprctl reload` restores the configured look (same mechanism as
 *       Auto Tile: runtime hl.config changes have no undo), profile back to
 *       balanced, Caffeine released. Auto Tile's float rule is re-asserted
 *       after the reload wipes the Lua state.
 */
Singleton {
    id: root

    property bool on: false
    // Caffeine state the user had before Game Mode grabbed it — restored on
    // exit instead of unconditionally switching it off.
    property bool priorInhibit: false

    onOnChanged: {
        if (root.on) {
            root.priorInhibit = Idle.inhibit;
            Quickshell.execDetached(["hyprctl", "eval",
                "hl.config({animations={enabled=false}, decoration={blur={enabled=false}, shadow={enabled=false}}})"]);
            Quickshell.execDetached(["powerprofilesctl", "set", "performance"]);
            Idle.toggleInhibit(true);
        } else {
            Quickshell.execDetached(["hyprctl", "reload"]);
            Quickshell.execDetached(["powerprofilesctl", "set", "balanced"]);
            Idle.toggleInhibit(root.priorInhibit);
            reassertTimer.restart();
        }
    }

    // hyprctl reload rebuilds a fresh Lua state — put Auto Tile's runtime
    // float rule back if it was active.
    Timer {
        id: reassertTimer
        interval: 1500
        onTriggered: {
            if (!WindowTiling.autoTile)
                Quickshell.execDetached(["hyprctl", "eval",
                    "if not OAI_FLOAT_RULE then OAI_FLOAT_RULE = hl.window_rule({match={class=\".*\"}, float=true, center=true}) end"]);
        }
    }
}
