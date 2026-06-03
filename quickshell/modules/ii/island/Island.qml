pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: islandWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:island"
            WlrLayershell.layer: WlrLayer.Top
            exclusiveZone: 0
            color: "transparent"

            anchors {
                top: true
            }

            implicitWidth: islandPill.width
            implicitHeight: islandPill.height + 8

            Rectangle {
                id: islandPill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 4

                width: 220
                height: 32
                radius: height / 2
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                StyledText {
                    anchors.centerIn: parent
                    text: "island"
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }
    }
}
