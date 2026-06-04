pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

// Full-screen transparent layer, present only while a notch surface is open.
// Registered FIRST in the panel family so it sits BELOW the three islands (their
// pills stay interactive) but above normal windows — clicking anywhere that
// isn't an island closes the open surface. Fixes click-outside-to-close.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: catcher
            required property var modelData
            screen: modelData

            visible: Island.openSurface !== ""
            WlrLayershell.namespace: "quickshell:islandCatcher"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: Island.close()
            }
        }
    }
}
