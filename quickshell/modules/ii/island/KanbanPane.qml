pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Kanban tab: three columns (To Do / In Progress / Done). Add (+), double-click
// to edit inline, × to delete, drag a card across columns to move it.
// State persisted via KanbanStore.
Item {
    id: pane
    property int editingId: -1
    property bool dragging: false
    property int dragId: -1
    property string dragText: ""
    property real dragX: 0
    property real dragY: 0

    readonly property var colTitles: ["To Do", "In Progress", "Done"]
    readonly property var colAccents: ["#8AB4F8", "#E7C56B", "#A0E7A0"]

    RowLayout {
        id: cols
        anchors.fill: parent
        spacing: 10

        Repeater {
            model: 3
            delegate: Rectangle {
                id: col
                required property int index
                readonly property int colNo: index
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.05)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle { width: 8; height: 8; radius: 4; color: pane.colAccents[col.colNo]; Layout.alignment: Qt.AlignVCenter }
                        StyledText {
                            text: pane.colTitles[col.colNo]
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: IslandStyle.textColor
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: KanbanStore.cardsIn(col.colNo).length
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: IslandStyle.subtextColor
                        }
                        MaterialSymbol {
                            text: "add"
                            iconSize: 18
                            color: IslandStyle.subtextColor
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    KanbanStore.add(col.colNo, "");
                                    pane.editingId = KanbanStore.lastId;
                                }
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: cardCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: cardCol
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: KanbanStore.cards.filter(c => c.col === col.colNo)
                                delegate: Rectangle {
                                    id: card
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(34, cardText.implicitHeight + 16)
                                    radius: 8
                                    color: cardHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
                                    opacity: (pane.dragging && pane.dragId === card.modelData.id) ? 0.3 : 1
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    HoverHandler { id: cardHover }

                                    StyledText {
                                        id: cardText
                                        visible: pane.editingId !== card.modelData.id
                                        anchors.left: parent.left
                                        anchors.right: delBtn.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 4
                                        text: card.modelData.text === "" ? "Untitled" : card.modelData.text
                                        color: card.modelData.text === "" ? IslandStyle.subtextColor : IslandStyle.textColor
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledTextInput {
                                        id: cardEdit
                                        visible: pane.editingId === card.modelData.id
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        text: card.modelData.text
                                        onVisibleChanged: if (visible) { forceActiveFocus(); selectAll(); }
                                        onAccepted: {
                                            KanbanStore.setText(card.modelData.id, text);
                                            pane.editingId = -1;
                                        }
                                        Keys.onEscapePressed: pane.editingId = -1
                                        onActiveFocusChanged: if (!activeFocus && pane.editingId === card.modelData.id) {
                                            KanbanStore.setText(card.modelData.id, text);
                                            pane.editingId = -1;
                                        }
                                    }

                                    MaterialSymbol {
                                        id: delBtn
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.rightMargin: 6
                                        visible: cardHover.hovered && pane.editingId !== card.modelData.id
                                        text: "close"
                                        iconSize: 15
                                        color: IslandStyle.subtextColor
                                        MouseArea { anchors.fill: parent; onClicked: KanbanStore.remove(card.modelData.id) }
                                    }

                                    MouseArea {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.right: delBtn.left
                                        property real startX: 0
                                        property real startY: 0
                                        property bool armed: false
                                        enabled: pane.editingId !== card.modelData.id
                                        onPressed: m => { startX = m.x; startY = m.y; armed = false; }
                                        onPositionChanged: m => {
                                            const dx = m.x - startX;
                                            const dy = m.y - startY;
                                            if (!armed && Math.sqrt(dx * dx + dy * dy) > 8) {
                                                armed = true;
                                                pane.dragging = true;
                                                pane.dragId = card.modelData.id;
                                                pane.dragText = card.modelData.text === "" ? "Untitled" : card.modelData.text;
                                            }
                                            if (armed) {
                                                const p = mapToItem(pane, m.x, m.y);
                                                pane.dragX = p.x;
                                                pane.dragY = p.y;
                                            }
                                        }
                                        onReleased: m => {
                                            if (armed) {
                                                const p = mapToItem(pane, m.x, m.y);
                                                const target = Math.max(0, Math.min(2, Math.floor(p.x / (pane.width / 3))));
                                                KanbanStore.move(pane.dragId, target);
                                            }
                                            pane.dragging = false;
                                            pane.dragId = -1;
                                            armed = false;
                                        }
                                        onDoubleClicked: pane.editingId = card.modelData.id
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
        visible: pane.dragging
        z: 100
        x: pane.dragX - width / 2
        y: pane.dragY - 18
        width: 180
        height: 36
        radius: 8
        color: Qt.rgba(0.1, 0.1, 0.12, 0.95)
        border.width: 1
        border.color: IslandStyle.accent
        StyledText {
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: Text.AlignVCenter
            text: pane.dragText
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: IslandStyle.textColor
        }
    }
}
