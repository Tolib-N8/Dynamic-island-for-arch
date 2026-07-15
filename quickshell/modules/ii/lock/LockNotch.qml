import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.island

// Lock-screen notch. Idle: padlock + "Locked". While media is available it
// morphs into THE desktop notch's media row (NotchMediaRow — same component,
// same Cava/CoverArt feeds), so the locked notch is pixel-identical to the
// unlocked one and stays in sync with future notch changes.
Item {
    id: root

    readonly property var player: MprisController.activePlayer
    readonly property bool mediaAvailable: (player?.trackTitle ?? "").length > 0
    readonly property list<real> goeyCurve: [0.34, 1.22, 0.64, 1, 1, 1]
    readonly property int cornerRadius: 18

    implicitWidth: notchBody.width
    implicitHeight: notchBody.height

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
        // Same sizing rule as the desktop notch's expanded media state:
        // content width + 36, height 40.
        width: (root.mediaAvailable ? mediaRow.implicitWidth : lockRow.implicitWidth) + 36
        height: 40
        color: IslandStyle.pillColor
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.cornerRadius
        bottomRightRadius: root.cornerRadius
        clip: true

        Behavior on width {
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

        // ---- media: THE notch media row ----
        NotchMediaRow {
            id: mediaRow
            anchors.centerIn: parent
            opacity: root.mediaAvailable ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
    }
}
