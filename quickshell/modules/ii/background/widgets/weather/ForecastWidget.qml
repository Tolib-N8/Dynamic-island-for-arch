import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

// Desktop forecast card: three days of wttr.in forecast in the same soft
// pastel style as the cookie clock. Draggable (placementStrategy "free").
AbstractBackgroundWidget {
    id: root

    configEntryName: "forecast"

    readonly property var days: Weather.data?.forecast ?? []

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    visible: opacity > 0 && root.days.length > 0

    StyledDropShadow {
        target: card
    }

    Rectangle {
        id: card
        radius: 26
        color: Appearance.colors.colSurfaceContainer
        opacity: 0.88
        implicitWidth: col.implicitWidth + 44
        implicitHeight: col.implicitHeight + 36

        ColumnLayout {
            id: col
            anchors.centerIn: parent
            spacing: 10

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: Icons.getWeatherIcon(Weather.data?.wCode ?? "113") ?? "cloud"
                    iconSize: 30
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: (Weather.data?.temp ?? "--°") + "  " + (Weather.data?.city ?? "")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.expressive
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            Repeater {
                model: root.days
                delegate: RowLayout {
                    id: dayRow
                    required property var modelData
                    required property int index
                    spacing: 12
                    Layout.fillWidth: true

                    StyledText {
                        Layout.preferredWidth: 46
                        text: dayRow.index === 0 ? Translation.tr("Today")
                            : Qt.formatDate(new Date(dayRow.modelData.date), "ddd")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    MaterialSymbol {
                        text: Icons.getWeatherIcon(dayRow.modelData.wCode) ?? "cloud"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colPrimary
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: `${dayRow.modelData.max}°`
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: `${dayRow.modelData.min}°`
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.45)
                    }
                }
            }
        }
    }
}
