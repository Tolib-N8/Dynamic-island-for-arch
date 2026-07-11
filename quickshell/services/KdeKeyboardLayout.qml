pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Keyboard layout for the Plasma edition, via KWin's org.kde.KeyboardLayouts
 * DBus API. `current` is the active layout's short name ("us", "ru").
 * Live updates come from a dbus-monitor subscription to layoutChanged.
 * Inert on Hyprland (where HyprlandXkb covers this).
 */
Singleton {
    id: root

    readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0

    property string current: ""
    property int layoutCount: 0

    function refresh() {
        if (!root.onHyprland)
            fetchProc.running = true;
    }

    function next() {
        Quickshell.execDetached(["busctl", "--user", "call", "org.kde.keyboard",
                                 "/Layouts", "org.kde.KeyboardLayouts", "switchToNextLayout"]);
    }

    Process {
        id: fetchProc
        command: ["bash", "-c",
            "busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayout; " +
            "busctl --user call org.kde.keyboard /Layouts org.kde.KeyboardLayouts getLayoutsList"]
        stdout: StdioCollector {
            onStreamFinished: {
                // line 1: `u 0` — active index; line 2: `a(sss) 2 "us" "" "..." "ru" "" "..."`
                const idxMatch = text.match(/^u\s+(\d+)/m);
                const names = [];
                const listMatch = text.match(/a\(sss\)\s+\d+\s+(.*)/);
                if (listMatch) {
                    const re = /"([^"]*)"\s+"[^"]*"\s+"[^"]*"/g;
                    let m;
                    while ((m = re.exec(listMatch[1])) !== null)
                        names.push(m[1]);
                }
                root.layoutCount = names.length;
                if (idxMatch && names.length > 0)
                    root.current = names[Number(idxMatch[1])] ?? "";
            }
        }
    }

    // Refetch on every layoutChanged / layoutListChanged signal.
    Process {
        running: !root.onHyprland
        command: ["dbus-monitor", "--session", "type='signal',interface='org.kde.KeyboardLayouts'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("layoutChanged") || line.includes("layoutListChanged"))
                    root.refresh();
            }
        }
    }

    Component.onCompleted: refresh()
}
