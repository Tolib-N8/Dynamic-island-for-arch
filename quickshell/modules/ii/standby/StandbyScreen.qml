import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.island

// StandBy — Apple-style night panel. After a few idle minutes the screen dims
// to near-black with a huge clock, the date, and the notch media row when
// something is playing. The layer is fully click-through and driven by
// ext-idle-notify: any input ends the idle state and fades it away.
Scope {
    id: root

    readonly property bool standbyActive: idle.isIdle && !GlobalStates.screenLocked

    IdleMonitor {
        id: idle
        enabled: (Config.options?.standby.enable ?? true) && !GlobalStates.screenLocked
        timeout: (Config.options?.standby.timeoutMinutes ?? 3) * 60
        // Video playback / Caffeine hold idle inhibitors — StandBy must not
        // interrupt a movie. (Verified: with this false it does.)
        respectInhibitors: true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: standbyWindow
            required property var modelData
            screen: modelData
            visible: contentRoot.opacity > 0.01

            WlrLayershell.namespace: "quickshell:standby"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // Fully click-through: waking input must reach the compositor's idle
            // tracker (and the apps beneath), not this veil.
            mask: Region {}

            Rectangle {
                id: contentRoot
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.93)
                opacity: root.standbyActive ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 600; easing.type: Easing.InOutQuad }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: DateTime.time
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: 150
                            weight: Font.Medium
                        }
                        color: Qt.rgba(1, 1, 1, 0.85)
                    }
                    // Full localized date — "суббота, 19 июля"-style
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.locale().toString(DateTime.clock.date, "dddd, d MMMM")
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: Appearance.font.pixelSize.huge
                            weight: Font.Medium
                        }
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Weather: icon · temperature · city, accent-tinted
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        spacing: 8
                        visible: (Weather.data?.temp ?? 0) !== 0

                        MaterialSymbol {
                            text: Icons.getWeatherIcon(Weather.data?.wCode ?? "113") ?? "cloud"
                            fill: 1
                            iconSize: 26
                            color: ColorUtils.transparentize(IslandStyle.accent, 0.15)
                        }
                        StyledText {
                            text: Weather.data?.temp ?? ""
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Qt.rgba(1, 1, 1, 0.65)
                        }
                        StyledText {
                            text: Weather.data?.city ?? ""
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                    }

                    NotchMediaRow {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 30
                        visible: (MprisController.activePlayer?.trackTitle ?? "").length > 0
                    }
                }
            }
        }
    }
}
