import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.island

// Lock-screen notch. Idle: a padlock + "Locked" pill hanging from the top
// edge, same silhouette as the desktop notch (square top, rounded bottom,
// concave shoulders, goey morph). While media is available it widens into a
// mini player: cover art, title/artist, prev / play-pause / next — usable
// without unlocking.
Item {
    id: root

    readonly property var player: MprisController.activePlayer
    readonly property bool mediaAvailable: (player?.trackTitle ?? "").length > 0
    readonly property bool playing: player?.isPlaying ?? false
    readonly property list<real> goeyCurve: [0.34, 1.22, 0.64, 1, 1, 1]
    readonly property int cornerRadius: 18

    implicitWidth: notchBody.width
    implicitHeight: notchBody.height

    // Cover art — same cache path as the desktop notch (one qs process, so a
    // track that played before locking is usually already downloaded).
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property string artFile: artUrl.length > 0 ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
    property string displayedArt: ""
    onArtFileChanged: {
        if (artFile.length === 0) {
            displayedArt = "";
            return;
        }
        artDl.outFile = artFile;
        artDl.targetUrl = artUrl;
        artDl.running = true;
    }
    Process {
        id: artDl
        property string targetUrl: ""
        property string outFile: ""
        command: ["bash", "-c", `[ -f '${outFile}' ] || curl -4 -sSL '${targetUrl}' -o '${outFile}'`]
        onExited: code => {
            if (code === 0)
                root.displayedArt = Qt.resolvedUrl(artDl.outFile);
        }
    }

    RoundCorner {
        corner: RoundCorner.CornerEnum.TopRight
        color: IslandStyle.pillColor
        implicitSize: 20
        anchors.right: notchBody.left
        anchors.rightMargin: -1
        anchors.top: parent.top
    }
    RoundCorner {
        corner: RoundCorner.CornerEnum.TopLeft
        color: IslandStyle.pillColor
        implicitSize: 20
        anchors.left: notchBody.right
        anchors.leftMargin: -1
        anchors.top: parent.top
    }

    Rectangle {
        id: notchBody
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.mediaAvailable ? 400 : lockRow.implicitWidth + 44
        height: root.mediaAvailable ? 76 : 42
        color: IslandStyle.pillColor
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.cornerRadius
        bottomRightRadius: root.cornerRadius
        clip: true

        Behavior on width {
            NumberAnimation { duration: 330; easing.bezierCurve: root.goeyCurve }
        }
        Behavior on height {
            NumberAnimation { duration: 330; easing.bezierCurve: root.goeyCurve }
        }

        // ---- idle: padlock + Locked ----
        RowLayout {
            id: lockRow
            anchors.centerIn: parent
            spacing: 9
            opacity: root.mediaAvailable ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            MaterialSymbol {
                text: "lock"
                fill: 1
                iconSize: 17
                color: IslandStyle.textColor
            }
            StyledText {
                text: Translation.tr("Locked")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: IslandStyle.textColor
            }
        }

        // ---- media: art · title/artist · controls ----
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            opacity: root.mediaAvailable ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 46
                implicitHeight: 46
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.10)
                    visible: artImg.status !== Image.Ready
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 22
                        color: IslandStyle.subtextColor
                    }
                }
                Image {
                    id: artImg
                    anchors.fill: parent
                    source: root.displayedArt
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle { width: 46; height: 46; radius: 8 }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: IslandStyle.textColor
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                    elide: Text.ElideRight
                }
            }

            component ControlIcon: MaterialSymbol {
                id: ctl
                property var action
                Layout.alignment: Qt.AlignVCenter
                iconSize: 24
                fill: 1
                color: ctlHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: ctlHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ctl.action()
                }
            }

            ControlIcon { text: "skip_previous"; action: () => root.player?.previous() }
            ControlIcon { text: root.playing ? "pause" : "play_arrow"; iconSize: 28; action: () => root.player?.togglePlaying() }
            ControlIcon { text: "skip_next"; action: () => root.player?.next() }
        }
    }
}
