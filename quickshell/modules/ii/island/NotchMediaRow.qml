import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// THE notch media row — art tile · equalizer bars · play/pause — shared by
// the desktop notch (media state) and the lock-screen notch, so both render
// the exact same thing from the same Cava/CoverArt feeds.
RowLayout {
    id: root

    readonly property var player: MprisController.activePlayer
    readonly property bool playing: player?.isPlaying ?? false

    // Downsampled equalizer bars from the cava points (0..1).
    readonly property int barCount: 22
    readonly property var barValues: {
        const pts = Cava.points;
        const n = barCount;
        let out = [];
        for (let i = 0; i < n; i++) {
            if (pts && pts.length > 0) {
                const idx = Math.floor(i * pts.length / n);
                out.push(Math.max(0, Math.min(1, (pts[idx] ?? 0) / 1000)));
            } else {
                out.push(0);
            }
        }
        return out;
    }

    spacing: 10

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 26
        implicitHeight: 26
        radius: 7
        color: Qt.rgba(1, 1, 1, 0.08)
        StyledImage {
            id: artImg
            anchors.fill: parent
            source: CoverArt.displayedArt
            fillMode: Image.PreserveAspectCrop
            visible: CoverArt.displayedArt !== "" && status === Image.Ready
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artImg.width
                    height: artImg.height
                    radius: 7
                }
            }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !artImg.visible
            text: "music_note"
            iconSize: 16
            color: IslandStyle.textColor
        }
    }

    // Equalizer bars
    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 112
        implicitHeight: 24
        Row {
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: root.barCount
                delegate: Item {
                    id: barCell
                    required property int index
                    width: 3
                    height: 24
                    Rectangle {
                        anchors.centerIn: parent
                        width: 3
                        radius: 1.5
                        color: IslandStyle.accent
                        height: Math.max(3, (root.barValues[barCell.index] ?? 0) * 22)
                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                    }
                }
            }
        }
    }

    MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter
        iconSize: 24
        fill: 1
        color: IslandStyle.textColor
        text: root.playing ? "pause" : "play_arrow"
        MouseArea {
            anchors.fill: parent
            onClicked: root.player?.togglePlaying()
        }
    }
}
