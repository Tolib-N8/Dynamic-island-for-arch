pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * macOS-style privacy signals:
 *  - micActive / micApps: something records the microphone (PipeWire
 *    source-outputs, monitor-capture streams like cava filtered out);
 *  - screensharing: the compositor reports an active screencast
 *    (Hyprland `screencast` event).
 */
Singleton {
    id: root

    property bool micActive: false
    property list<string> micApps: []
    property bool screensharing: false

    function refreshMic() {
        micProc.running = true;
    }

    Process {
        id: micProc
        command: ["python3", "-c", `
import json, subprocess
def pj(args):
    return json.loads(subprocess.run(["pactl", "--format=json"] + args, capture_output=True, text=True).stdout or "[]")
monitors = {s["index"] for s in pj(["list", "sources"]) if s.get("name", "").endswith(".monitor")}
apps = []
for so in pj(["list", "source-outputs"]):
    if so.get("source") in monitors:
        continue  # captures speaker output (cava etc), not the mic
    props = so.get("properties", {})
    name = props.get("application.name") or props.get("media.name") or "app"
    if name.lower() in ("cava", "speech-dispatcher"):
        continue
    apps.append(name)
print(json.dumps(sorted(set(apps))))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const apps = JSON.parse(text.trim() || "[]");
                    root.micApps = apps;
                    root.micActive = apps.length > 0;
                } catch (e) {
                    root.micApps = [];
                    root.micActive = false;
                }
            }
        }
    }

    // React to PipeWire stream lifecycle (tethered like the other watchers).
    Process {
        running: true
        stdinEnabled: true
        command: ["bash", "-c",
            "pactl subscribe & W=$!; cat >/dev/null; kill $W 2>/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("source-output"))
                    root.refreshMic();
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "screencast")
                root.screensharing = event.data.split(",")[0] === "1";
        }
    }

    Component.onCompleted: refreshMic()
}
