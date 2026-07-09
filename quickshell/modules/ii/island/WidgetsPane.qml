pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Mpris

// Widgets tab content: media player · quick toggles · volume/mic sliders ·
// calendar · notification centre · power-profile selector · live stat bars.
Item {
    id: pane

    // Notification source: the built-in server (Hyprland) OR the KDE mirror
    // (Plasma, via bridge/notif_bridge.py). They're mutually exclusive per
    // platform, so show whichever is populated.
    readonly property bool usingMirror: Notifications.list.length === 0 && NotificationMirror.list.length > 0
    // Newest first. Notifications.list is appended oldest→newest, so reverse it;
    // NotificationMirror.list is already newest-first.
    readonly property var notifList: pane.usingMirror ? NotificationMirror.list : Notifications.list.slice().reverse()
    function clearNotifs() {
        if (pane.usingMirror)
            NotificationMirror.clear();
        else
            Notifications.discardAllNotifications();
    }
    // Click a notification row → invoke its "default" action (open the app / follow
    // the notification). Only works for the built-in server's notifications.
    function openNotif(nobj) {
        if (pane.usingMirror || !nobj || !nobj.notificationId)
            return;
        const acts = nobj.actions ?? [];
        let id = "";
        for (let i = 0; i < acts.length; i++)
            if (acts[i].identifier === "default") { id = "default"; break; }
        if (id === "" && acts.length > 0)
            id = acts[0].identifier;
        if (id !== "")
            Notifications.attemptInvokeAction(nobj.notificationId, id);
    }

    // ---------- reusable bits ----------
    component ToggleChip: Rectangle {
        id: chip
        property string icon
        property string label
        property string sublabel
        property bool active: false
        signal toggled
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: active ? Qt.rgba(0.54, 0.70, 0.97, 0.18) : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: active ? Qt.rgba(0.54, 0.70, 0.97, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8
            MaterialSymbol {
                text: chip.icon
                iconSize: 18
                fill: chip.active ? 1 : 0
                color: chip.active ? IslandStyle.accent : IslandStyle.textColor
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2
                StyledText {
                    Layout.fillWidth: true
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: IslandStyle.textColor
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: chip.sublabel !== ""
                    text: chip.sublabel
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                    elide: Text.ElideRight
                }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: chip.toggled() }
    }

    component HSlider: Rectangle {
        id: sl
        property string icon
        property real value: 0
        signal moved(real v)
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.05)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 8
            MaterialSymbol { text: sl.icon; iconSize: 16; color: IslandStyle.textColor }
            Item {
                Layout.fillWidth: true
                implicitHeight: 30
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        height: parent.height
                        radius: 2.5
                        width: parent.width * Math.max(0, Math.min(1, sl.value))
                        color: IslandStyle.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: m => sl.moved(Math.max(0, Math.min(1, m.x / width)))
                    onPositionChanged: m => { if (pressed) sl.moved(Math.max(0, Math.min(1, m.x / width))); }
                }
            }
        }
    }

    // ---------- layout ----------
    RowLayout {
        anchors.fill: parent
        spacing: 10

        // === Media player ===
        Rectangle {
            id: mp
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            radius: 14
            color: Qt.rgba(1, 1, 1, 0.05)

            readonly property var player: MprisController.activePlayer
            readonly property string artUrl: player?.trackArtUrl ?? ""
            readonly property string artPath: artUrl.length > 0 ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
            property string artLocal: ""
            readonly property string trackKey: player?.trackTitle ?? ""
            onTrackKeyChanged: artLocal = ""
            onArtPathChanged: {
                if (artPath.length === 0)
                    return;
                artDl.outFile = artPath;
                artDl.url = artUrl;
                artDl.running = true;
            }
            Process {
                id: artDl
                property string url: ""
                property string outFile: ""
                command: ["bash", "-c", `[ -f '${outFile}' ] || curl -4 -sSL '${url}' -o '${outFile}'`]
                onExited: code => { if (code === 0) mp.artLocal = Qt.resolvedUrl(artDl.outFile); }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 88
                    implicitHeight: 88
                    Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.08) }
                    StyledImage {
                        id: art
                        anchors.fill: parent
                        source: mp.artLocal
                        fillMode: Image.PreserveAspectCrop
                        visible: mp.artLocal !== "" && status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: art.width; height: art.height; radius: width / 2 }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: !art.visible
                        text: "music_note"
                        iconSize: 32
                        color: IslandStyle.subtextColor
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12; height: 12; radius: 6
                        color: "#000000"
                        opacity: 0.85
                        visible: art.visible
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: mp.player?.trackTitle || "Nothing playing"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: IslandStyle.textColor
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: mp.player?.trackArtist || ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                    elide: Text.ElideRight
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16
                    MaterialSymbol {
                        text: "skip_previous"; iconSize: 22; fill: 1; color: IslandStyle.textColor
                        MouseArea { anchors.fill: parent; onClicked: mp.player?.previous() }
                    }
                    MaterialSymbol {
                        text: (mp.player?.isPlaying ?? false) ? "pause_circle" : "play_circle"
                        iconSize: 32; fill: 1; color: IslandStyle.textColor
                        MouseArea { anchors.fill: parent; onClicked: mp.player?.togglePlaying() }
                    }
                    MaterialSymbol {
                        text: "skip_next"; iconSize: 22; fill: 1; color: IslandStyle.textColor
                        MouseArea { anchors.fill: parent; onClicked: mp.player?.next() }
                    }
                }
            }
        }

        // === Center column: toggles · sliders · calendar+notifications ===
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ToggleChip {
                    icon: Network.materialSymbol
                    label: "Wi-Fi"
                    sublabel: Network.wifiEnabled ? (Network.networkName || "On") : "Off"
                    active: Network.wifiEnabled
                    onToggled: Network.toggleWifi()
                }
                ToggleChip {
                    icon: "bluetooth"
                    label: "Bluetooth"
                    sublabel: BluetoothStatus.enabled ? (BluetoothStatus.connected ? "Connected" : "On") : "Off"
                    active: BluetoothStatus.enabled
                    onToggled: { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; }
                }
                ToggleChip {
                    icon: "nightlight"
                    label: "Night Mode"
                    sublabel: Hyprsunset.temperatureActive ? "Enabled" : "Disabled"
                    active: Hyprsunset.temperatureActive
                    onToggled: Hyprsunset.toggleTemperature()
                }
                ToggleChip {
                    icon: "coffee"
                    label: "Caffeine"
                    sublabel: Idle.inhibit ? "Enabled" : "Disabled"
                    active: Idle.inhibit
                    onToggled: Idle.toggleInhibit()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                HSlider {
                    icon: (Audio.sink?.audio?.muted ?? false) ? "volume_off" : "volume_up"
                    value: Audio.sink?.audio?.volume ?? 0
                    onMoved: v => { if (Audio.sink?.audio) Audio.sink.audio.volume = v; }
                }
                HSlider {
                    icon: (Audio.source?.audio?.muted ?? false) ? "mic_off" : "mic"
                    value: Audio.source?.audio?.volume ?? 0
                    onMoved: v => { if (Audio.source?.audio) Audio.source.audio.volume = v; }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 232
                    Layout.fillHeight: true
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.05)
                    WidgetCalendar {
                        anchors.fill: parent
                        anchors.margins: 10
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.05)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Notifications"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: IslandStyle.textColor
                            }
                            MaterialSymbol {
                                text: "delete_sweep"
                                iconSize: 18
                                color: IslandStyle.subtextColor
                                visible: pane.notifList.length > 0
                                MouseArea { anchors.fill: parent; onClicked: pane.clearNotifs() }
                            }
                        }
                        ColumnLayout {
                            visible: pane.notifList.length === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Item { Layout.fillHeight: true }
                            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "notifications_off"; iconSize: 30; color: IslandStyle.subtextColor }
                            StyledText { Layout.alignment: Qt.AlignHCenter; text: "No notifications"; font.pixelSize: Appearance.font.pixelSize.smaller; color: IslandStyle.subtextColor }
                            Item { Layout.fillHeight: true }
                        }
                        ListView {
                            visible: pane.notifList.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 5
                            model: pane.notifList
                            delegate: Rectangle {
                                id: notifRow
                                required property var modelData
                                readonly property bool clickable: !pane.usingMirror && (modelData?.actions?.length ?? 0) > 0
                                width: ListView.view.width
                                implicitHeight: ncol.implicitHeight + 12
                                radius: 8
                                color: notifMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                MouseArea {
                                    id: notifMouse
                                    anchors.fill: parent
                                    hoverEnabled: notifRow.clickable
                                    cursorShape: notifRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        pane.openNotif(notifRow.modelData);
                                        Island.close();   // dismiss the dashboard after acting
                                    }
                                }
                                ColumnLayout {
                                    id: ncol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.appName
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: IslandStyle.subtextColor
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.summary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: IslandStyle.textColor
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: (modelData.body ?? "") !== ""
                                        text: modelData.body ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: IslandStyle.subtextColor
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // === Right column: vertical power-profile slider (Saver↔Normal↔Performance) ===
        WidgetModeSlider {
            Layout.preferredWidth: 170
            Layout.fillHeight: true
        }
    }
}
