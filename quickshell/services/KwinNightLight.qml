pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * KWin Night Light control for the Plasma edition (hyprsunset can't change
 * gamma under KWin). Toggle = flip NightColor's Active key (pinning Constant
 * mode when enabling, so it warms immediately regardless of schedule) and tell
 * KWin to reconfigure. `active` mirrors the temperature KWin actually applies,
 * not our last wish — so an externally-scheduled night light reads correctly.
 */
Singleton {
    id: root

    property bool active: false

    function refresh() {
        stateProc.running = true;
    }

    function toggle() {
        const on = !root.active;
        root.active = on;  // optimistic; refresh() confirms from KWin shortly
        // --notify is what makes KWin pick the change up live (its config
        // watcher listens for kconfig change broadcasts, not file writes).
        Quickshell.execDetached(["bash", "-c", on
            ? "kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true; " +
              "kwriteconfig6 --notify --file kwinrc --group NightColor --key Mode Constant"
            : "kwriteconfig6 --notify --file kwinrc --group NightColor --key Active false"]);
        confirmTimer.restart();
    }

    Process {
        id: stateProc
        command: ["busctl", "--user", "get-property", "org.kde.KWin",
                  "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight", "currentTemperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/u\s+(\d+)/);
                if (m)
                    root.active = Number(m[1]) < 6000;  // day is 6500K
            }
        }
    }

    // The transition to the target temperature takes a couple of seconds.
    Timer {
        id: confirmTimer
        interval: 2500
        onTriggered: root.refresh()
    }
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
