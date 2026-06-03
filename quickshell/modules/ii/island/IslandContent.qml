import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    // ---- State machine ----
    // "idle" = invisible. Others = visible/expanded.
    property string islandState: "idle"

    // Sizes per state
    readonly property int idleWidth: 8
    readonly property int idleHeight: 6
    readonly property int volumeWidth: 180
    readonly property int activeHeight: 26

    readonly property bool active: islandState !== "idle"

    implicitWidth: pill.width
    implicitHeight: Appearance.sizes.baseBarHeight

    // ---- Volume trigger ----
    // end-4 sets GlobalStates.osdVolumeOpen when you scroll volume on the bar.
    Connections {
        target: GlobalStates
        function onOsdVolumeOpenChanged() {
            if (GlobalStates.osdVolumeOpen) {
                root.islandState = "volume";
                hideTimer.restart();
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.islandState = "idle"
    }

    // ---- The morphing pill ----
    Rectangle {
        id: pill
        anchors.centerIn: parent

        width: root.active ? root.volumeWidth : root.idleWidth
        height: root.active ? root.activeHeight : root.idleHeight
        radius: height / 2

        color: Appearance.colors.colLayer1
        border.width: root.active ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
        opacity: root.active ? 1 : 0

        // Goey spring morph
        Behavior on width {
            NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        Behavior on height {
            NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
        }

        // ---- Volume content ----
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 8
            visible: root.islandState === "volume"

            MaterialSymbol {
                text: (Audio.sink?.audio?.muted ?? false) ? "volume_off"
                    : (Audio.sink?.audio?.volume ?? 0) < 0.01 ? "volume_mute"
                    : (Audio.sink?.audio?.volume ?? 0) < 0.5 ? "volume_down"
                    : "volume_up"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle { // volume track
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 4
                radius: 2
                color: Appearance.colors.colLayer0

                Rectangle { // volume fill
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * (Audio.sink?.audio?.volume ?? 0)
                    height: parent.height
                    radius: parent.radius
                    color: Appearance.colors.colOnLayer1

                    Behavior on width {
                        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }
                }
            }
        }
    }
}
