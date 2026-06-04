pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Vertical power-profile slider with 3 stops: Performance (top) · Normal · Saver
// (bottom). Drag the knob (snaps to nearest stop) or click a label/track to set.
// Uses powerprofilesctl get/set.
Rectangle {
    id: root
    radius: 14
    color: Qt.rgba(1, 1, 1, 0.05)

    property string current: "balanced"
    // top → bottom
    readonly property var stops: [
        { "key": "performance", "icon": "rocket_launch", "label": "Performance" },
        { "key": "balanced", "icon": "balance", "label": "Normal" },
        { "key": "power-saver", "icon": "energy_savings_leaf", "label": "Saver" }
    ]
    function indexOfCurrent() {
        const i = root.stops.findIndex(s => s.key === root.current);
        return i < 0 ? 1 : i;
    }
    function setMode(key) {
        root.current = key;
        Quickshell.execDetached(["powerprofilesctl", "set", key]);
    }

    Process {
        id: getProf
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser { onRead: d => root.current = d.trim() }
    }
    Component.onCompleted: getProf.running = true

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // --- track + knob ---
        Item {
            id: trackArea
            Layout.fillHeight: true
            Layout.preferredWidth: 24
            readonly property real usable: height - knob.height
            function yForIndex(i) { return root.stops.length > 1 ? i / (root.stops.length - 1) * usable : 0; }
            function indexForY(y) {
                const f = usable > 0 ? Math.max(0, Math.min(1, y / usable)) : 0;
                return Math.round(f * (root.stops.length - 1));
            }

            Rectangle { // track
                anchors.horizontalCenter: parent.horizontalCenter
                width: 6
                height: parent.height
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.12)
            }
            Rectangle { // fill from bottom up to the knob (more = more performance)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 6
                radius: 3
                height: Math.max(0, parent.height - (knob.y + knob.height / 2))
                color: IslandStyle.accent
            }
            Repeater { // stop ticks
                model: root.stops.length
                delegate: Rectangle {
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 8
                    height: 8
                    radius: 4
                    y: trackArea.yForIndex(index) + knob.height / 2 - 4
                    color: Qt.rgba(1, 1, 1, 0.25)
                }
            }
            MouseArea { // click track → nearest stop
                anchors.fill: parent
                onClicked: m => root.setMode(root.stops[trackArea.indexForY(m.y - knob.height / 2)].key)
            }
            Rectangle { // knob
                id: knob
                width: 24
                height: 24
                radius: 12
                anchors.horizontalCenter: parent.horizontalCenter
                color: IslandStyle.accent
                border.width: 3
                border.color: "#0A0A0C"
                property bool dragging: false
                Behavior on y { enabled: !knob.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Binding {
                    target: knob
                    property: "y"
                    value: trackArea.yForIndex(root.indexOfCurrent())
                    when: !knob.dragging
                    restoreMode: Binding.RestoreBinding
                }
                MouseArea {
                    anchors.fill: parent
                    drag.target: knob
                    drag.axis: Drag.YAxis
                    drag.minimumY: 0
                    drag.maximumY: trackArea.usable
                    onPressed: knob.dragging = true
                    onReleased: {
                        const i = trackArea.indexForY(knob.y);
                        knob.dragging = false;
                        root.setMode(root.stops[i].key);
                    }
                }
            }
        }

        // --- labels ---
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: root.stops
                delegate: Item {
                    id: lbl
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property bool sel: root.current === lbl.modelData.key
                    RowLayout {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        MaterialSymbol {
                            text: lbl.modelData.icon
                            iconSize: 17
                            fill: lbl.sel ? 1 : 0
                            color: lbl.sel ? IslandStyle.accent : IslandStyle.subtextColor
                        }
                        StyledText {
                            text: lbl.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: lbl.sel ? Font.DemiBold : Font.Normal
                            color: lbl.sel ? IslandStyle.textColor : IslandStyle.subtextColor
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.setMode(lbl.modelData.key) }
                }
            }
        }
    }
}
