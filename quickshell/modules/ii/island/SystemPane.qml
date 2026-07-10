pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Dashboard "System" tab — live machine stats. Especially useful on the Plasma
// (notch-only) edition where the side islands that used to carry resources/battery
// are gone. Pure services (ResourceUsage / Battery / SystemInfo), so it works the
// same under Hyprland and KWin.
Item {
    id: pane

    function pct(v) {
        return Math.round(Math.max(0, Math.min(1, v)) * 100) + "%";
    }
    // green → orange → red as a load ramps up
    function loadColor(v) {
        return v >= 0.85 ? "#E05561" : v >= 0.6 ? "#E8A23D" : "#7EE787";
    }
    // battery is the opposite: full is good (green), empty is bad (red)
    function batteryColor(v, charging) {
        return charging ? "#7AA2F7" : v <= 0.15 ? "#E05561" : v <= 0.3 ? "#E8A23D" : "#7EE787";
    }

    // A labelled meter card: icon + name, big percentage, progress bar, sub caption.
    component StatCard: Rectangle {
        id: card
        property string icon
        property string label
        property real value: 0        // 0..1
        property string sub: ""
        property color barColor: pane.loadColor(value)
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 14
        color: Qt.rgba(1, 1, 1, 0.05)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol { text: card.icon; iconSize: 18; color: IslandStyle.subtextColor }
                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: IslandStyle.subtextColor
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: pane.pct(card.value)
                font.pixelSize: Appearance.font.pixelSize.huge ?? 28
                font.weight: Font.Bold
                color: IslandStyle.textColor
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * Math.max(0, Math.min(1, card.value))
                    color: card.barColor
                    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 320 } }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: card.sub !== ""
                text: card.sub
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: IslandStyle.subtextColor
                elide: Text.ElideRight
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ---- meters row ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            StatCard {
                icon: "memory"
                label: "CPU"
                value: ResourceUsage.cpuUsage
                sub: pane.pct(ResourceUsage.cpuUsage) + " in use"
            }
            StatCard {
                icon: "developer_board"
                label: "Memory"
                value: ResourceUsage.memoryUsedPercentage
                sub: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed) + " / " + ResourceUsage.maxAvailableMemoryString
            }
            StatCard {
                icon: "swap_horiz"
                label: "Swap"
                value: ResourceUsage.swapUsedPercentage
                sub: ResourceUsage.swapTotal > 1
                     ? ResourceUsage.kbToGbString(ResourceUsage.swapUsed) + " / " + ResourceUsage.maxAvailableSwapString
                     : "No swap"
            }
            StatCard {
                icon: Battery.isCharging ? "battery_charging_full" : "battery_full"
                label: "Battery"
                visible: Battery.available
                Layout.preferredWidth: Battery.available ? -1 : 0
                value: Battery.percentage
                barColor: pane.batteryColor(Battery.percentage, Battery.isCharging)
                sub: !Battery.available ? "" : Battery.isCharging ? "Charging" : Battery.isPluggedIn ? "Plugged in" : "On battery"
            }
        }

        // ---- AI limits strip (CodexBar-style remaining quota) ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.05)
            visible: AiUsage.available
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 14
                MaterialSymbol { text: "data_usage"; iconSize: 16; color: IslandStyle.subtextColor }
                StyledText {
                    text: "AI limits"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: IslandStyle.subtextColor
                }
                Repeater {
                    model: AiUsage.providers
                    RowLayout {
                        id: prov
                        required property var modelData
                        spacing: 6
                        StyledText {
                            text: prov.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: IslandStyle.textColor
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 56
                            implicitHeight: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: parent.width * (AiUsage.saturated(prov.modelData) ? 1
                                       : Math.max(0, Math.min(1, (prov.modelData.remainingPct ?? 0) / 100)))
                                color: AiUsage.chipColor(prov.modelData)
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }
                        StyledText {
                            text: (AiUsage.saturated(prov.modelData)
                                   ? "at max" : AiUsage.remainingLabel(prov.modelData) + " left")
                                  + (prov.modelData.estimate ? "*" : "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: AiUsage.chipColor(prov.modelData)
                        }
                        StyledText {
                            text: "· resets " + AiUsage.resetIn(prov.modelData)
                                  + (prov.modelData.plan ? " · " + prov.modelData.plan : "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: IslandStyle.subtextColor
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: "* estimate"
                    visible: AiUsage.providers.some(p => p.estimate)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Qt.rgba(1, 1, 1, 0.35)
                }
            }
        }

        // ---- system info strip ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.05)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                MaterialSymbol { text: "computer"; iconSize: 16; color: IslandStyle.subtextColor }
                StyledText {
                    Layout.fillWidth: true
                    text: `${SystemInfo.username}@${SystemInfo.distroName}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: IslandStyle.textColor
                    elide: Text.ElideRight
                }
                StyledText {
                    text: [SystemInfo.desktopEnvironment, SystemInfo.windowingSystem].filter(x => x && x.length > 0).join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                    elide: Text.ElideRight
                }
            }
        }
    }
}
