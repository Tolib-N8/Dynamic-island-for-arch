pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Shared cava audio-visualizer feed. Runs only while media is actually
 * playing; every consumer (desktop notch, lock-screen notch) reads the same
 * points instead of spawning its own cava.
 */
Singleton {
    id: root

    property list<real> points: []

    Process {
        running: MprisController.activePlayer?.isPlaying ?? false
        onRunningChanged: {
            if (!running)
                root.points = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}
