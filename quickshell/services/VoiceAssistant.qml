pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// State for the "Code" voice assistant, so the notch can be its overlay (replacing
// the assistant's standalone quickshell overlay.qml). Driven over IPC by the
// assistant (see plasma/shell.qml `voice` handler + ai-assistant/scripts/common.py):
//   mode: hidden | idle | bars | text
// Live mic/TTS levels come through a file the assistant already writes
// (/tmp/assistant_levels), polled here — avoids an IPC round-trip per audio frame.
Singleton {
    id: root

    property string mode: "hidden"     // hidden | idle | bars | text
    property string text: ""
    property real level: 0             // 0..1, live audio RMS while mode === "bars"
    readonly property bool active: mode !== "hidden"

    readonly property string levelFile: "/tmp/assistant_levels"

    function show() { root.mode = "bars"; }
    function idle() { root.mode = "idle"; }
    function hide() { root.mode = "hidden"; root.text = ""; root.level = 0; }
    function setText(msg) { root.text = msg || ""; root.mode = "text"; }
    function setLevel(v) { root.level = Math.max(0, Math.min(1, v)); }

    FileView {
        id: levelView
        path: root.levelFile
        blockLoading: false
        onLoadedChanged: {
            const raw = levelView.text();
            if (raw === undefined || raw === null)
                return;
            const v = parseFloat(String(raw).trim());
            if (!isNaN(v))
                root.level = Math.max(0, Math.min(1, v));
        }
    }
    // Poll the level file only while showing live bars.
    Timer {
        running: root.mode === "bars"
        interval: 33
        repeat: true
        onTriggered: levelView.reload()
    }
}
