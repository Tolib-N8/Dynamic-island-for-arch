pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Cover art of the active MPRIS track, downloaded once to a stable local
 * cache file (players rewrite/clear trackArtUrl mid-track, which made the art
 * flicker or vanish when used directly). `displayedArt` is only cleared on an
 * actual TRACK change and only set once the cache file is confirmed present.
 * Shared by the desktop notch and the lock-screen notch.
 */
Singleton {
    id: root

    readonly property var activePlayer: MprisController.activePlayer
    readonly property string artUrl: activePlayer?.trackArtUrl ?? ""
    readonly property string artFilePath: artUrl.length > 0 ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
    property string displayedArt: ""

    readonly property string trackKey: activePlayer?.trackTitle ?? ""
    onTrackKeyChanged: displayedArt = ""

    onArtFilePathChanged: {
        if (artFilePath.length === 0)
            return; // transient empty URL — keep the current art
        downloader.outFile = artFilePath;
        downloader.targetUrl = artUrl;
        downloader.running = true;
    }

    Process {
        id: downloader
        property string targetUrl: ""
        property string outFile: ""
        command: ["bash", "-c", `[ -f '${outFile}' ] || curl -4 -sSL '${targetUrl}' -o '${outFile}'`]
        onExited: code => {
            if (code === 0)
                root.displayedArt = Qt.resolvedUrl(downloader.outFile);
        }
    }
}
