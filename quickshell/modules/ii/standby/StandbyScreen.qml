import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
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
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: DateTime.longDate
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Qt.rgba(1, 1, 1, 0.40)
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
