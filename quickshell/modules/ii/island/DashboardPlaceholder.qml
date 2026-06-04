pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Temporary centred icon+label pane used by the dashboard tabs until their real
// content lands (Widgets → Phase B, Kanban → Phase C).
Item {
    id: ph
    property string icon: ""
    property string label: ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: ph.icon
            iconSize: 40
            color: IslandStyle.subtextColor
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: ph.label
            font.pixelSize: Appearance.font.pixelSize.normal
            color: IslandStyle.subtextColor
        }
    }
}
