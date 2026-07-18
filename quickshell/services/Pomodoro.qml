pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Pomodoro focus timer. Work/break phases cycle until stopped; each phase end
 * fires a notification. The notch shows the countdown while running.
 */
Singleton {
    id: root

    property int workMinutes: 25
    property int breakMinutes: 5

    property bool running: false
    property string phase: "work"      // work | break
    property int remaining: workMinutes * 60
    property int cyclesDone: 0         // completed work phases this session

    readonly property string display: {
        const m = Math.floor(remaining / 60);
        const s = remaining % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    function start() {
        phase = "work";
        remaining = workMinutes * 60;
        running = true;
    }
    function stop() {
        running = false;
        phase = "work";
        remaining = workMinutes * 60;
    }
    function toggle() {
        running ? stop() : start();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            root.remaining -= 1;
            if (root.remaining > 0)
                return;
            if (root.phase === "work") {
                root.cyclesDone += 1;
                root.phase = "break";
                root.remaining = root.breakMinutes * 60;
                Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-i", "alarm",
                    "Break time", `Focus block ${root.cyclesDone} done — rest ${root.breakMinutes} min`]);
            } else {
                root.phase = "work";
                root.remaining = root.workMinutes * 60;
                Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-i", "alarm",
                    "Back to work", `Focus block ${root.cyclesDone + 1} — ${root.workMinutes} min`]);
            }
        }
    }
}
