pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Center notch — top-attached, morphing. THE STAR.
//
// Shape: hangs from the top-center; square top corners flush with the screen edge,
// rounded bottom (constant radius), concave RoundCorner shoulders blending into the
// top edge. Borderless solid fill.
//
// State machine (precedence: agent > media > volume/brightness > notification > idle;
// volume/brightness/notification wired). `open` is a click-toggled full view.
//   idle      — small empty shape
//   expanded  — transient OSD content (the active `expandedSource`)
//   open      — large, click-toggled
// Goey overshoot morph (cubic-bezier 0.34,1.22,0.64,1). Triggers use the underlying
// service VALUE/signal, not the flicker-prone OSD flags.
Scope {
    id: root

    readonly property list<real> goeyCurve: [0.34, 1.22, 0.64, 1, 1, 1]
    readonly property int morphDuration: 330
    readonly property int shoulderSize: 20
    readonly property int cornerRadius: 18
    readonly property int maxWidth: 480
    readonly property int maxHeight: 300

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notchWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:islandNotch"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
            }
            margins {
                top: 0
            }

            implicitWidth: root.maxWidth + root.shoulderSize * 2
            implicitHeight: root.maxHeight
            mask: Region {
                item: notch
            }

            // --- state machine ---
            property bool clickedOpen: false
            // The active transient OSD source: "volume" | "brightness" | "notification" | "".
            property string expandedSource: ""
            property string islandState: clickedOpen ? "open" : (expandedSource !== "" ? "expanded" : "idle")

            // One shared auto-hide timer; latest trigger wins.
            Timer {
                id: hideTimer
                onTriggered: notchWindow.expandedSource = ""
            }
            function trigger(src, ms) {
                expandedSource = src;
                hideTimer.interval = ms;
                hideTimer.restart();
            }

            // Notification payload (for the notification content).
            property string notifApp: ""
            property string notifSummary: ""
            property string notifIcon: ""

            readonly property var brightnessMonitor: Brightness.getMonitorForScreen(notchWindow.screen)

            // --- triggers (off the real service value/signal) ---
            Connections {
                target: Audio.sink?.audio ?? null
                function onVolumeChanged() {
                    if (Audio.ready)
                        notchWindow.trigger("volume", 2000);
                }
                function onMutedChanged() {
                    if (Audio.ready)
                        notchWindow.trigger("volume", 2000);
                }
            }
            Connections {
                target: Brightness
                function onBrightnessChanged() {
                    notchWindow.trigger("brightness", 2000);
                }
            }
            Connections {
                target: Notifications
                function onNotify(notification) {
                    notchWindow.notifApp = notification.appName ?? "";
                    notchWindow.notifSummary = notification.summary ?? "";
                    notchWindow.notifIcon = notification.appIcon ?? "";
                    notchWindow.trigger("notification", 4000);
                }
            }

            // Active content's natural width → drives the expanded morph target.
            property real contentWidth: {
                switch (expandedSource) {
                case "volume":
                    return volumeUI.implicitWidth;
                case "brightness":
                    return brightnessUI.implicitWidth;
                case "notification":
                    return notifUI.implicitWidth;
                default:
                    return 0;
                }
            }
            property real targetWidth: islandState === "open" ? root.maxWidth
                : islandState === "expanded" ? Math.min(root.maxWidth, contentWidth + 44)
                : 180
            property real targetHeight: islandState === "open" ? root.maxHeight
                : islandState === "expanded" ? 54
                : 36

            // Concave shoulders (overlap notch 1px to avoid a seam).
            RoundCorner {
                corner: RoundCorner.CornerEnum.TopRight
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.right: notch.left
                anchors.rightMargin: -1
                anchors.top: parent.top
            }
            RoundCorner {
                corner: RoundCorner.CornerEnum.TopLeft
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.left: notch.right
                anchors.leftMargin: -1
                anchors.top: parent.top
            }

            Rectangle {
                id: notch
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                width: notchWindow.targetWidth
                height: notchWindow.targetHeight

                color: IslandStyle.pillColor
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: root.cornerRadius
                bottomRightRadius: root.cornerRadius

                Behavior on width {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }
                Behavior on height {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: notchWindow.clickedOpen = !notchWindow.clickedOpen
                }

                // ---- volume ----
                RowLayout {
                    id: volumeUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.expandedSource === "volume" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: {
                            const a = Audio.sink?.audio;
                            if (!a || a.muted)
                                return "volume_off";
                            if (a.volume <= 0.0001)
                                return "volume_mute";
                            if (a.volume < 0.5)
                                return "volume_down";
                            return "volume_up";
                        }
                    }
                    OsdBar {
                        value: Audio.sink?.audio?.volume ?? 0
                        accent: (Audio.sink?.audio?.muted ?? false) ? Qt.rgba(1, 1, 1, 0.4) : IslandStyle.accent
                    }
                    OsdPercent { value: Audio.sink?.audio?.volume ?? 0 }
                }

                // ---- brightness ----
                RowLayout {
                    id: brightnessUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.expandedSource === "brightness" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: {
                            const b = notchWindow.brightnessMonitor?.brightness ?? 1;
                            return b < 0.5 ? "brightness_low" : "brightness_high";
                        }
                    }
                    OsdBar {
                        value: notchWindow.brightnessMonitor?.brightness ?? 0
                        accent: "#FFD479"
                    }
                    OsdPercent { value: notchWindow.brightnessMonitor?.brightness ?? 0 }
                }

                // ---- notification ----
                RowLayout {
                    id: notifUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.expandedSource === "notification" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    Loader {
                        Layout.alignment: Qt.AlignVCenter
                        active: notchWindow.notifIcon !== ""
                        visible: active
                        sourceComponent: IconImage {
                            implicitSize: 22
                            source: Quickshell.iconPath(notchWindow.notifIcon, "dialog-information-symbolic")
                        }
                    }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: notchWindow.notifIcon === ""
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: "notifications"
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: -2
                        StyledText {
                            Layout.maximumWidth: 280
                            visible: notchWindow.notifApp !== ""
                            text: notchWindow.notifApp
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: IslandStyle.subtextColor
                        }
                        StyledText {
                            Layout.maximumWidth: 280
                            text: notchWindow.notifSummary
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: IslandStyle.textColor
                        }
                    }
                }
            }
        }
    }

    // Small reusable OSD bits (level bar + percent label).
    component OsdBar: Rectangle {
        id: bar
        property real value: 0
        property color accent: IslandStyle.accent
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 110
        implicitHeight: 6
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.18)
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: bar.height
            width: bar.width * Math.max(0, Math.min(1, bar.value))
            radius: height / 2
            color: bar.accent
            Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        }
    }
    component OsdPercent: StyledText {
        property real value: 0
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 26
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(Math.max(0, Math.min(1, value)) * 100)}`
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: IslandStyle.textColor
    }
}
