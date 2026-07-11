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

    // "" = normal widgets · "wifi"/"bt" = a detail page in the centre column
    property string detailPage: ""

    // A soft rfkill block (Fn radio key, resume quirk) leaves BlueZ in
    // "off-blocked", where setting Powered silently fails — lift the block
    // before powering on.
    function toggleBluetooth(): void {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return;
        if (adapter.enabled)
            adapter.enabled = false;
        else
            Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth && bluetoothctl power on"]);
    }

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
        property bool expandable: false
        signal toggled
        signal expanded
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
            MaterialSymbol {
                visible: chip.expandable
                text: "chevron_right"
                iconSize: 16
                color: IslandStyle.subtextColor
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: chip.expandable ? chip.expanded() : chip.toggled()
        }
        // The icon remains a direct on/off switch even when the body opens a page.
        MouseArea {
            visible: chip.expandable
            width: 38
            height: parent.height
            onClicked: chip.toggled()
        }
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


    component MiniSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal clicked
        implicitWidth: 36
        implicitHeight: 20
        radius: 10
        color: checked ? IslandStyle.accent : Qt.rgba(1, 1, 1, 0.15)
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 2
            x: sw.checked ? sw.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            color: "#FFFFFF"
        }
        MouseArea { anchors.fill: parent; onClicked: sw.clicked() }
    }

    component PageHeader: RowLayout {
        id: ph
        property string title
        property bool busy: false
        property bool powered: false
        signal back
        signal refresh
        signal togglePower
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            implicitWidth: 26; implicitHeight: 26; radius: 13
            color: backHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            HoverHandler { id: backHover }
            MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 18; color: IslandStyle.textColor }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ph.back() }
        }
        StyledText {
            text: ph.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: IslandStyle.textColor
        }
        Item { Layout.fillWidth: true }
        MaterialSymbol {
            text: "refresh"
            iconSize: 17
            color: ph.busy ? IslandStyle.accent : IslandStyle.subtextColor
            RotationAnimation on rotation { running: ph.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ph.refresh() }
        }
        MiniSwitch { checked: ph.powered; onClicked: ph.togglePower() }
    }

    // Wi-Fi detail page: scan, pick a network, inline password prompt.
    component WifiPage: ColumnLayout {
        spacing: 6
        onVisibleChanged: if (visible && Network.wifiEnabled) Network.rescanWifi()

        PageHeader {
            title: "Wi-Fi"
            busy: Network.wifiScanning
            powered: Network.wifiEnabled
            onBack: pane.detailPage = ""
            onRefresh: Network.rescanWifi()
            onTogglePower: Network.toggleWifi()
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: wifiCol.implicitHeight
            ColumnLayout {
                id: wifiCol
                width: parent.width
                spacing: 4

                StyledText {
                    visible: Network.friendlyWifiNetworks.length === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 14
                    text: !Network.wifiEnabled ? "Wi-Fi is off" : Network.wifiScanning ? "Scanning…" : "No networks found"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                }

                Repeater {
                    model: Network.friendlyWifiNetworks
                    delegate: Rectangle {
                        id: netRow
                        required property var modelData
                        readonly property bool isTarget: Network.wifiConnectTarget === modelData
                        Layout.fillWidth: true
                        implicitHeight: netCol.implicitHeight + 12
                        radius: 8
                        color: modelData.active ? Qt.rgba(0.54, 0.70, 0.97, 0.14)
                             : netMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09)
                             : Qt.rgba(1, 1, 1, 0.05)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (netRow.modelData.askingPassword) return;
                                if (!netRow.modelData.active) Network.connectToWifiNetwork(netRow.modelData);
                            }
                        }
                        ColumnLayout {
                            id: netCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 4
                            RowLayout {
                                spacing: 8
                                MaterialSymbol {
                                    readonly property int s: netRow.modelData?.strength ?? 0
                                    text: s > 80 ? "signal_wifi_4_bar" : s > 60 ? "network_wifi_3_bar" : s > 40 ? "network_wifi_2_bar" : s > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                                    iconSize: 17
                                    color: netRow.modelData.active ? IslandStyle.accent : IslandStyle.textColor
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: netRow.modelData?.ssid || "Unknown"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: IslandStyle.textColor
                                    elide: Text.ElideRight
                                }
                                MaterialSymbol {
                                    visible: text !== ""
                                    text: netRow.modelData.active ? "check" : netRow.isTarget ? "sync" : netRow.modelData.isSecure ? "lock" : ""
                                    iconSize: 15
                                    color: netRow.modelData.active ? IslandStyle.accent : IslandStyle.subtextColor
                                }
                            }
                            // Inline password prompt (appears when nmcli asks for secrets)
                            RowLayout {
                                visible: netRow.modelData?.askingPassword ?? false
                                spacing: 6
                                onVisibleChanged: {
                                    Island.wantsKeyboard = visible;
                                    if (visible) pwField.forceActiveFocus();
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 13
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)
                                    TextInput {
                                        id: pwField
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        inputMethodHints: Qt.ImhSensitiveData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: IslandStyle.textColor
                                        clip: true
                                        onAccepted: Network.changePassword(netRow.modelData, text)
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: pwField.text === ""
                                            text: "Password"
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: IslandStyle.subtextColor
                                        }
                                    }
                                }
                                Rectangle {
                                    implicitWidth: 26; implicitHeight: 26; radius: 13
                                    color: IslandStyle.accent
                                    MaterialSymbol { anchors.centerIn: parent; text: "arrow_forward"; iconSize: 15; color: "#000000" }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Network.changePassword(netRow.modelData, pwField.text)
                                    }
                                }
                                MaterialSymbol {
                                    text: "close"
                                    iconSize: 16
                                    color: IslandStyle.subtextColor
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: netRow.modelData.askingPassword = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Bluetooth detail page: discover, connect/disconnect, pair/forget.
    component BtPage: ColumnLayout {
        spacing: 6
        // Discover nearby devices only while the page is open.
        onVisibleChanged: {
            if (Bluetooth.defaultAdapter)
                Bluetooth.defaultAdapter.discovering = visible && Bluetooth.defaultAdapter.enabled;
        }

        PageHeader {
            title: "Bluetooth"
            busy: Bluetooth.defaultAdapter?.discovering ?? false
            powered: BluetoothStatus.enabled
            onBack: pane.detailPage = ""
            onRefresh: { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = true; }
            onTogglePower: pane.toggleBluetooth()
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: btCol.implicitHeight
            ColumnLayout {
                id: btCol
                width: parent.width
                spacing: 4

                StyledText {
                    visible: BluetoothStatus.friendlyDeviceList.length === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 14
                    text: BluetoothStatus.enabled ? "No devices found" : "Bluetooth is off"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: IslandStyle.subtextColor
                }

                Repeater {
                    model: BluetoothStatus.friendlyDeviceList
                    delegate: Rectangle {
                        id: devRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: devInner.implicitHeight + 14
                        radius: 8
                        color: modelData.connected ? Qt.rgba(0.54, 0.70, 0.97, 0.14)
                             : devMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09)
                             : Qt.rgba(1, 1, 1, 0.05)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        MouseArea {
                            id: devMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: devRow.modelData.connected ? devRow.modelData.disconnect() : devRow.modelData.connect()
                        }
                        RowLayout {
                            id: devInner
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            MaterialSymbol {
                                text: Icons.getBluetoothDeviceMaterialSymbol(devRow.modelData?.icon || "")
                                iconSize: 17
                                color: devRow.modelData.connected ? IslandStyle.accent : IslandStyle.textColor
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: devRow.modelData?.name || "Unknown device"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: IslandStyle.textColor
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: {
                                        if (!devRow.modelData?.paired) return "";
                                        let t = devRow.modelData.connected ? "Connected" : "Paired";
                                        if (devRow.modelData.batteryAvailable) t += ` · ${Math.round(devRow.modelData.battery * 100)}%`;
                                        return t;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: IslandStyle.subtextColor
                                    elide: Text.ElideRight
                                }
                            }
                            // pair / forget
                            MaterialSymbol {
                                readonly property bool p: devRow.modelData?.paired ?? false
                                text: p ? "link_off" : "add_link"
                                iconSize: 16
                                color: pfHover.hovered ? (p ? "#E05561" : IslandStyle.accent) : IslandStyle.subtextColor
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: pfHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: parent.p ? devRow.modelData.forget() : devRow.modelData.pair()
                                }
                            }
                        }
                    }
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
        // (swapped for a Wi-Fi / Bluetooth detail page when a chip is expanded)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                visible: pane.detailPage === ""
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ToggleChip {
                        icon: Network.materialSymbol
                        label: "Wi-Fi"
                        sublabel: Network.wifiEnabled ? (Network.networkName || "On") : "Off"
                        active: Network.wifiEnabled
                        expandable: true
                        onToggled: Network.toggleWifi()
                        onExpanded: pane.detailPage = "wifi"
                    }
                    ToggleChip {
                        icon: "bluetooth"
                        label: "Bluetooth"
                        sublabel: BluetoothStatus.enabled ? (BluetoothStatus.connected ? "Connected" : "On") : "Off"
                        active: BluetoothStatus.enabled
                        expandable: true
                        onToggled: pane.toggleBluetooth()
                        onExpanded: pane.detailPage = "bt"
                    }
                    ToggleChip {
                        icon: "nightlight"
                        label: "Night Mode"
                        // Plasma: hyprsunset can't touch KWin's gamma — drive
                        // KWin Night Light instead.
                        readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
                        sublabel: (onHyprland ? Hyprsunset.temperatureActive : KwinNightLight.active) ? "Enabled" : "Disabled"
                        active: onHyprland ? Hyprsunset.temperatureActive : KwinNightLight.active
                        onToggled: onHyprland ? Hyprsunset.toggleTemperature() : KwinNightLight.toggle()
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

            WifiPage {
                anchors.fill: parent
                visible: pane.detailPage === "wifi"
            }
            BtPage {
                anchors.fill: parent
                visible: pane.detailPage === "bt"
            }
        }

        // === Right column: vertical power-profile slider (Saver↔Normal↔Performance) ===
        WidgetModeSlider {
            Layout.preferredWidth: 170
            Layout.fillHeight: true
        }
    }
}
