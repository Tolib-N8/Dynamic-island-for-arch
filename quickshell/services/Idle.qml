pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    // No-op used by shell.qml to instantiate this lazy singleton at startup —
    // otherwise the inhibitor and the `idle` IPC only exist after the widgets
    // pane is first opened.
    function wake() {}

    function restoreFromPersistent() {
        if (!Persistent.isNewHyprlandInstance) {
            root.inhibit = Persistent.states.idle.inhibit;
        } else {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    // Persistent may already be ready by the time this singleton instantiates
    // (it's lazy) — handle both orders.
    Component.onCompleted: if (Persistent.ready) restoreFromPersistent()
    Connections {
        target: Persistent
        function onReadyChanged() { root.restoreFromPersistent(); }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // KWin only honours the Wayland idle-inhibit protocol for visible surfaces,
    // so the invisible 0x0 window below does nothing on Plasma. Hold a real
    // inhibition through kde-inhibit instead; `cat` blocks on our stdin pipe and
    // exits when quickshell drops it, so nothing leaks if we crash.
    readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
    Process {
        command: ["kde-inhibit", "--power", "--screenSaver", "cat"]
        stdinEnabled: true
        running: !root.onHyprland && root.inhibit
    }

    IpcHandler {
        target: "idle"
        function toggleInhibit(): void { root.toggleInhibit(); }
        function status(): string { return root.inhibit ? "on" : "off"; }
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
