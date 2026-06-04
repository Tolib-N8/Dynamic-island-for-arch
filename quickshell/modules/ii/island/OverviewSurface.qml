pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// Workspace overview (USECASE 4): live WS 1–10 grid with per-window app icons.
// Click a window → focus, right-click → close, click empty cell → switch,
// drag a window icon onto another cell → move it there. Vanilla-Hyprland
// dispatchers only (no end-4 hl.dsp.* plugin calls). Live via HyprlandData.
FocusScope {
    id: surf
    focus: true
    Keys.onEscapePressed: Island.close()

    readonly property int activeWs: Hyprland.focusedWorkspace?.id ?? 1
    readonly property var windows: HyprlandData.windowList
    function winsIn(ws) {
        return surf.windows.filter(w => w.workspace.id === ws);
    }

    // drag state
    property bool dragging: false
    property string dragAddr: ""
    property string dragIcon: ""
    property real dragX: 0
    property real dragY: 0

    Item {
        id: grid
        anchors.fill: parent
        anchors.margins: 12
        readonly property real cellW: (width - 4 * 8) / 5
        readonly property real cellH: (height - 8) / 2

        GridLayout {
            anchors.fill: parent
            columns: 5
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: 10
                delegate: Rectangle {
                    id: cell
                    required property int index
                    readonly property int wsId: cell.index + 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: 2
                    border.color: surf.activeWs === cell.wsId ? IslandStyle.accent : "transparent"

                    // empty-cell click → switch workspace (declared first → below icons)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Hyprland.dispatch(`workspace ${cell.wsId}`);
                            Island.close();
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: cell.wsId
                        font.pixelSize: 40
                        font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, 0.06)
                        visible: surf.winsIn(cell.wsId).length === 0
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 7
                        text: "Workspace " + cell.wsId
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: IslandStyle.subtextColor
                    }

                    Flow {
                        anchors.fill: parent
                        anchors.topMargin: 24
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        anchors.bottomMargin: 7
                        spacing: 4
                        Repeater {
                            model: surf.winsIn(cell.wsId)
                            delegate: Item {
                                id: chip
                                required property var modelData
                                width: 34
                                height: 34
                                opacity: (surf.dragging && surf.dragAddr === chip.modelData.address) ? 0.3 : 1

                                IconImage {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: Quickshell.iconPath(AppSearch.guessIcon(chip.modelData.class), "application-x-executable")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    property real sx: 0
                                    property real sy: 0
                                    property bool armed: false
                                    property bool suppressClick: false
                                    onPressed: m => { sx = m.x; sy = m.y; armed = false; }
                                    onPositionChanged: m => {
                                        if (!(m.buttons & Qt.LeftButton))
                                            return;
                                        const dx = m.x - sx;
                                        const dy = m.y - sy;
                                        if (!armed && Math.sqrt(dx * dx + dy * dy) > 8) {
                                            armed = true;
                                            surf.dragging = true;
                                            surf.dragAddr = chip.modelData.address;
                                            surf.dragIcon = Quickshell.iconPath(AppSearch.guessIcon(chip.modelData.class), "application-x-executable");
                                        }
                                        if (armed) {
                                            const p = mapToItem(surf, m.x, m.y);
                                            surf.dragX = p.x;
                                            surf.dragY = p.y;
                                        }
                                    }
                                    onReleased: m => {
                                        const wasDragging = armed;
                                        if (wasDragging) {
                                            const p = mapToItem(grid, m.x, m.y);
                                            const col = Math.max(0, Math.min(4, Math.floor(p.x / grid.cellW)));
                                            const row = Math.max(0, Math.min(1, Math.floor(p.y / grid.cellH)));
                                            const target = row * 5 + col + 1;
                                            if (target !== chip.modelData.workspace.id)
                                                Hyprland.dispatch(`movetoworkspacesilent ${target},address:${chip.modelData.address}`);
                                        }
                                        suppressClick = wasDragging;
                                        surf.dragging = false;
                                        surf.dragAddr = "";
                                        armed = false;
                                    }
                                    onClicked: m => {
                                        if (suppressClick) {
                                            suppressClick = false;
                                            return;
                                        }
                                        if (m.button === Qt.LeftButton) {
                                            Hyprland.dispatch(`focuswindow address:${chip.modelData.address}`);
                                            Island.close();
                                        } else if (m.button === Qt.RightButton) {
                                            Hyprland.dispatch(`closewindow address:${chip.modelData.address}`);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // floating drag proxy
    Rectangle {
        visible: surf.dragging
        z: 100
        x: surf.dragX - 18
        y: surf.dragY - 18
        width: 36
        height: 36
        radius: 9
        color: Qt.rgba(0.1, 0.1, 0.12, 0.95)
        border.width: 1
        border.color: IslandStyle.accent
        IconImage {
            anchors.fill: parent
            anchors.margins: 4
            source: surf.dragIcon
        }
    }
}
