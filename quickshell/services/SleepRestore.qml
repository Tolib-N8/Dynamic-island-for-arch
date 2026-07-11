pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

/**
 * Post-resume fixups. The BT adapter re-registers after suspend (fresh rfkill
 * index) and regularly comes back soft-blocked / unpowered, leaving the user
 * to revive it by hand. Watch logind's PrepareForSleep: snapshot the adapter
 * state going down; if it was ON, unblock + power it back up on resume.
 * Deliberately does nothing when the user had turned BT off themselves.
 */
Singleton {
    id: root

    property bool btWasOn: false

    Process {
        running: true
        stdinEnabled: true
        // Tethered to our stdin pipe so restarts don't leave orphaned monitors.
        command: ["bash", "-c",
            "dbus-monitor --system \"type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'\" & W=$!; cat >/dev/null; kill $W 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("boolean true")) {
                    root.btWasOn = Bluetooth.defaultAdapter?.enabled ?? false;
                } else if (line.includes("boolean false") && root.btWasOn) {
                    btRestoreProc.running = true;
                }
            }
        }
    }

    Process {
        id: btRestoreProc
        // A few seconds for btusb to re-probe before poking the fresh adapter.
        command: ["bash", "-c", "sleep 3; rfkill unblock bluetooth; bluetoothctl power on"]
    }
}
