pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.wallpaperSelector
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// Center notch — top-attached, morphing. THE STAR.
//
// Shape: hangs from top-center; square top corners flush with the screen edge,
// rounded bottom (constant radius), concave RoundCorner shoulders. Borderless fill.
// Reserves a top strip (exclusiveZone) so maximized windows sit BELOW the islands.
//
// State machine (precedence: agent > media > volume/brightness > notification > idle).
// Transient OSDs auto-hide; media shows only while PLAYING. `open` is click-toggled.
// Goey overshoot morph (cubic-bezier 0.34,1.22,0.64,1).
Scope {
    id: root

    // Off Hyprland (e.g. KWin/Plasma) the notch must NOT grab keyboard focus:
    // a focused layer-shell surface becomes KWin's "active window", and shortcuts
    // like Meta+Q ("Close Window") would then close the notch. Pointer input still
    // works without keyboard focus, so clicks/toggles/allow-deny are unaffected.
    readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0

    readonly property list<real> goeyCurve: [0.34, 1.22, 0.64, 1, 1, 1]
    readonly property int morphDuration: 330
    readonly property int shoulderSize: 20
    readonly property int cornerRadius: 18
    readonly property int maxWidth: 1100          // widest open surface (overview) — also sizes the window
    readonly property int maxHeight: 400
    readonly property int expandedMaxWidth: 480   // cap for transient OSDs (volume/brightness/media/notif)
    readonly property int reservedStrip: 40       // top space reserved for the island strip

    // Open-state surface sizes — notch body w×h per named surface (Island.openSurface).
    readonly property var surfaceSizes: ({
            "dashboard": { "w": 1040, "h": 360 },
            "overview":  { "w": 1100, "h": 300 },
            "launcher":  { "w": 560,  "h": 380 },
            "power":     { "w": 320,  "h": 92  },
            "tools":     { "w": 440,  "h": 84  },
            "agent":     { "w": 460,  "h": 300 },
            "wallpapers": { "w": 1200, "h": 620 }
        })

    // Media (shared across monitors). Show only while actively playing.
    readonly property var activePlayer: MprisController.activePlayer
    readonly property bool mediaActive: activePlayer?.isPlaying ?? false

    // Cover art and the cava feed live in the CoverArt / Cava singletons —
    // shared with the lock-screen notch, which renders the same media row.

    // The monitor that currently has keyboard focus — where auto-opened surfaces
    // (e.g. an incoming permission) should appear. Falls back to the first screen.
    function focusedScreenName() {
        const n = Hyprland.focusedMonitor?.name ?? "";
        if (n.length > 0)
            return n;
        return Quickshell.screens.length > 0 ? (Quickshell.screens[0].name ?? "") : "";
    }

    // Surface control over IPC — shared by both editions (`qs -c <cfg> ipc call
    // island <surface>`): Hyprland keybinds and KDE shortcuts use the same verbs.
    IpcHandler {
        target: "island"

        function dashboard(): void { Island.toggle("dashboard", root.focusedScreenName()); }
        function agent(): void { Island.toggle("agent", root.focusedScreenName()); }
        function power(): void { Island.toggle("power", root.focusedScreenName()); }
        function wallpapers(): void { Island.toggle("wallpapers", root.focusedScreenName()); }
        function close(): void { Island.close(); }
        function morph(name: string): void { root.morphAll(name, 2800); }
        function pomodoro(): void { Pomodoro.toggle(); }
        // Clipboard history (Meta+V). Second invocation closes.
        function clipboard(): void {
            if (Island.openSurface === "dashboard") {
                Island.close();
            } else {
                Island.dashboardTab = 0;
                Island.dashboardDetail = "clip";
                Island.open("dashboard", root.focusedScreenName());
            }
        }
    }

    // Broadcast a transient morph to every monitor's notch (BT connects,
    // charging, the `island morph` IPC verb).
    signal morphAll(string src, int ms)

    // BT device-connected morph: diff the connected-address set; the freshly
    // connected device is shown AirPods-style (icon · name · battery).
    property var btMorphDevice: null
    property var _btAddrs: []
    readonly property var _btConnectedNow: BluetoothStatus.connectedDevices
    on_BtConnectedNowChanged: {
        const now = _btConnectedNow.map(d => d.address);
        const fresh = now.filter(a => root._btAddrs.indexOf(a) === -1);
        // Ignore the initial adopt (service just came up with devices already on).
        if (fresh.length > 0 && root._btAddrs.length + fresh.length === now.length && root._started) {
            root.btMorphDevice = root._btConnectedNow.find(d => d.address === fresh[0]) ?? null;
            if (root.btMorphDevice)
                root.morphAll("btdevice", 3200);
        }
        root._btAddrs = now;
    }
    property bool _started: false
    Timer { interval: 3000; running: true; onTriggered: root._started = true }

    // While locked the notch stays visible (layer rule above_lock) but is
    // reduced to "Locked" + the media row — close anything that was open.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                Island.close();
        }
    }

    // Permission is top-priority + sticky: auto-open the agent surface when a
    // request arrives (if nothing else is open) on the FOCUSED monitor, and close
    // back to compact when the last one is resolved.
    Connections {
        target: AgentService
        function onPendingPermissionsChanged() {
            if (AgentService.pendingPermissions.length > 0 && Island.openSurface === "" && !VoiceAssistant.active)
                Island.open("agent", root.focusedScreenName(), true);
            else if (AgentService.pendingPermissions.length === 0 && Island.openSurface === "agent")
                Island.close();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notchWindow
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:islandNotch"
            // Idle: Top — hides under fullscreen apps like a normal panel.
            // Surface open: Overlay — the expanded dashboard must draw ABOVE the
            // side-island pills (same-layer stacking on KWin ignores map order).
            WlrLayershell.layer: notchWindow.ownsOpen ? WlrLayer.Overlay : WlrLayer.Top
            // Grab keyboard only while THIS monitor's surface is open (Esc / search typing).
            // Only on Hyprland — see root.onHyprland: on KWin a focused layer surface
            // becomes the "active window" and Meta+Q would close the notch.
            // Island.wantsKeyboard: narrow exception (Wi-Fi password typing) — the
            // Meta+Q risk window is tiny while the user is actively typing a password.
            WlrLayershell.keyboardFocus: (notchWindow.ownsOpen && !GlobalStates.screenLocked && (root.onHyprland || Island.wantsKeyboard)) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            // Floating island — don't reserve a strip; windows pass under it like the
            // left/right islands (wallpaper breathes through the gaps).
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // ALL FOUR edges anchored → the window fills the monitor in LOGICAL
            // coordinates (like the framework's Background), correct on scaled
            // (eDP-1 @1.5) and rotated (DP-3) outputs. (Sizing via screen.width/height
            // — PHYSICAL pixels — is what blanked those monitors before.) Being
            // full-screen restores the click-anywhere-to-close catcher. It's
            // transparent and masked to just the notch body normally (rest is
            // click-through), to the whole screen while THIS monitor's surface is open.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // This monitor owns the open surface? Only ONE monitor shows a surface at
            // a time (see Island.qml) — so opening on this screen doesn't expand the
            // notch on the others.
            readonly property bool ownsOpen: Island.openSurface !== "" && Island.openScreen === (notchWindow.screen.name ?? "")

            // Lock-engage dip: slide out of view while Hyprland cannot render
            // above_lock layers (lock requested, lock surface not yet drawn),
            // then slide back in already wearing the Locked/media state.
            property real lockDipY: GlobalStates.lockEngaging ? -(targetHeight + root.shoulderSize + 8) : 0
            Behavior on lockDipY {
                NumberAnimation { duration: 160; easing.type: Easing.InQuad }
            }

            // Auto-opened surfaces (permission cards) mask only the notch body so
            // the rest of the screen stays usable; user-opened surfaces mask the
            // whole screen for click-outside-to-close.
            mask: Region {
                item: (notchWindow.ownsOpen && !Island.autoOpened) ? fullMaskItem : notch
            }
            Item { id: fullMaskItem; anchors.fill: parent }

            // --- state machine ---
            property string expandedSource: ""  // transient OSD: volume|brightness|notification|""
            // Agent-forward: an active agent outranks media for the notch display
            // (precedence: transient OSD > agent > media). Music keeps playing.
            property string displaySource: GlobalStates.screenLocked ? (root.mediaActive ? "media" : "locked")
                : VoiceAssistant.active ? "assistant"
                : (expandedSource !== "" ? expandedSource
                : (Pomodoro.running ? "pomodoro"
                : (AgentService.active ? "agent"
                : (root.mediaActive ? "media" : ""))))
            // open (a named surface is up ON THIS MONITOR) outranks transient OSDs,
            // which outrank idle.
            property string islandState: notchWindow.ownsOpen ? "open"
                : (displaySource !== "" ? "expanded" : "idle")

            Timer {
                id: hideTimer
                onTriggered: notchWindow.expandedSource = ""
            }
            function trigger(src, ms) {
                expandedSource = src;
                hideTimer.interval = ms;
                hideTimer.restart();
            }

            Connections {
                target: root
                function onMorphAll(src, ms) {
                    notchWindow.trigger(src, ms);
                }
            }
            // Plug / unplug the charger -> brief bolt + percentage morph.
            Connections {
                target: Battery
                function onIsPluggedInChanged() {
                    if (Battery.available)
                        notchWindow.trigger("charging", 2500);
                }
            }
            // Freshly unlocked -> a short welcome.
            Connections {
                target: GlobalStates
                function onScreenLockedChanged() {
                    if (!GlobalStates.screenLocked)
                        notchWindow.trigger("welcome", 2600);
                }
            }

            property string notifApp: ""
            property string notifSummary: ""
            property string notifIcon: ""
            property int notifId: 0
            property var notifActions: []

            // Click a notification → invoke its "default" action (open the app / follow
            // the notification), or the first action if there's no explicit default.
            // Works because the notch is the notification server (swaync disabled).
            function invokeNotifAction() {
                const acts = notchWindow.notifActions ?? [];
                let id = "";
                for (let i = 0; i < acts.length; i++)
                    if (acts[i].identifier === "default") { id = "default"; break; }
                if (id === "" && acts.length > 0)
                    id = acts[0].identifier;
                if (id !== "" && notchWindow.notifId > 0)
                    Notifications.attemptInvokeAction(notchWindow.notifId, id);
            }
            readonly property var brightnessMonitor: Brightness.getMonitorForScreen(notchWindow.screen)

            // attention flash when a NEW permission arrives
            property int _lastPending: 0
            property real permFlash: 0
            Connections {
                target: AgentService
                function onPendingPermissionsChanged() {
                    if (AgentService.pendingPermissions.length > notchWindow._lastPending)
                        permFlashAnim.restart();
                    notchWindow._lastPending = AgentService.pendingPermissions.length;
                }
            }
            SequentialAnimation {
                id: permFlashAnim
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 1; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 0.35; duration: 220; easing.type: Easing.InOutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 1; duration: 130; easing.type: Easing.OutQuad }
                NumberAnimation { target: notchWindow; property: "permFlash"; to: 0; duration: 650; easing.type: Easing.InQuad }
            }

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
                    notchWindow.notifId = notification.notificationId ?? 0;
                    notchWindow.notifActions = notification.actions ?? [];
                    notchWindow.trigger("notification", 4000);
                }
            }
            // Mirrored (Plasma) notifications morph the notch the same way. On
            // Hyprland this never fires (no bridge → NotificationMirror stays empty).
            Connections {
                target: NotificationMirror
                function onNotified(n) {
                    notchWindow.notifApp = n.appName ?? "";
                    notchWindow.notifSummary = n.summary ?? "";
                    notchWindow.notifIcon = n.appIcon ?? "";
                    notchWindow.notifId = 0;          // mirrored notifs have no invokable action
                    notchWindow.notifActions = [];
                    notchWindow.trigger("notification", 4000);
                }
            }

            property real contentWidth: {
                switch (displaySource) {
                case "volume":
                    return volumeUI.implicitWidth;
                case "brightness":
                    return brightnessUI.implicitWidth;
                case "notification":
                    return notifUI.implicitWidth;
                case "media":
                    return mediaUI.implicitWidth;
                case "agent":
                    return agentUI.implicitWidth;
                case "assistant":
                    return assistantUI.implicitWidth;
                case "locked":
                    return lockUI.implicitWidth;
                case "charging":
                    return chargingUI.implicitWidth;
                case "btdevice":
                    return btUI.implicitWidth;
                case "welcome":
                    return welcomeUI.implicitWidth;
                case "pomodoro":
                    return pomodoroUI.implicitWidth;
                default:
                    return 0;
                }
            }
            // Dashboard's Agents tab holds far less content than the widget tabs —
            // shrink the body to it (the size Behaviors animate the morph).
            readonly property bool dashboardCompact: Island.openSurface === "dashboard" && Island.dashboardCurrentTab === 3
            // Extra right-side room while the privacy dots are lit, so they sit
            // in clean space instead of over the content's right edge.
            readonly property real privacyPad: (PrivacyIndicators.micActive || PrivacyIndicators.screensharing) ? 26 : 0
            property real targetWidth: islandState === "open" ? (dashboardCompact ? 640 : (root.surfaceSizes[Island.openSurface]?.w ?? root.maxWidth))
                : islandState === "expanded" ? ((displaySource === "agent" ? (root.mediaActive ? 264 : 224) : Math.min(root.expandedMaxWidth, contentWidth + 36)) + privacyPad)
                : 180 + privacyPad
            property real targetHeight: islandState === "open" ? (dashboardCompact ? 300 : (root.surfaceSizes[Island.openSurface]?.h ?? root.maxHeight))
                : islandState === "expanded" ? (
                    displaySource === "assistant" ? Math.max(44, assistantUI.implicitHeight + 26) // 13 top + 13 bottom
                    : (displaySource === "media" || displaySource === "agent" || displaySource === "locked" || displaySource === "pomodoro" ? 40 : 54))
                : 36

            // Full-screen click-catcher (only while open). Sits BEHIND the notch
            // body — which absorbs its own clicks — so only clicks OUTSIDE the
            // notch close the surface. Same window → z-order is guaranteed.
            MouseArea {
                anchors.fill: parent
                enabled: notchWindow.islandState === "open" && !Island.autoOpened
                visible: enabled
                acceptedButtons: Qt.AllButtons
                onPressed: Island.close()
            }

            RoundCorner {
                corner: RoundCorner.CornerEnum.TopRight
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.right: notch.left
                anchors.rightMargin: -1
                anchors.top: parent.top
                transform: Translate { y: notchWindow.lockDipY }
            }
            RoundCorner {
                corner: RoundCorner.CornerEnum.TopLeft
                color: IslandStyle.pillColor
                implicitSize: root.shoulderSize
                anchors.left: notch.right
                anchors.leftMargin: -1
                anchors.top: parent.top
                transform: Translate { y: notchWindow.lockDipY }
            }

            Rectangle {
                id: notch
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                transform: Translate { y: notchWindow.lockDipY }

                width: notchWindow.targetWidth
                height: notchWindow.targetHeight

                color: IslandStyle.pillColor
                clip: true
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: root.cornerRadius
                bottomRightRadius: root.cornerRadius
                border.width: notchWindow.permFlash * 3
                border.color: Qt.rgba(0.91, 0.64, 0.24, notchWindow.permFlash)

                Behavior on width {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }
                Behavior on height {
                    NumberAnimation { duration: root.morphDuration; easing.bezierCurve: root.goeyCurve }
                }

                MouseArea {
                    anchors.fill: parent
                    // Click the notch body from idle/OSD → open the dashboard. When a
                    // surface is open, surfaceHost's absorber catches clicks (no
                    // accidental close); close via Esc or re-clicking the trigger pill.
                    onClicked: {
                        if (GlobalStates.screenLocked)
                            return; // Locked: only the media row's own controls work
                        // Clicking a notification invokes its default action (open the app /
                        // follow the notification) — the notch is the notification server,
                        // so actions work natively — then dismisses the morph.
                        if (notchWindow.displaySource === "notification") {
                            notchWindow.invokeNotifAction();
                            notchWindow.expandedSource = "";
                            return;
                        }
                        // open on THIS monitor (moves the surface here if another had it).
                        // Always the dashboard — an active agent just picks its tab, so
                        // Widgets/Kanban/System stay one click away while agents run.
                        if (notchWindow.displaySource === "agent")
                            Island.dashboardTab = 3;
                        Island.open("dashboard", notchWindow.screen.name);
                    }
                }

                // ---- volume ----
                RowLayout {
                    id: volumeUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "volume" ? 1 : 0
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

                // ---- idle: AI quota chips (CodexBar-style remaining-limit counters) ----
                RowLayout {
                    id: aiUsageIdleUI
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: notchWindow.islandState === "idle" && AiUsage.available ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    Repeater {
                        model: AiUsage.providers
                        RowLayout {
                            id: chip
                            required property var modelData
                            spacing: 5
                            StyledText {
                                text: chip.modelData.id === "claude" ? "CL" : chip.modelData.id === "codex" ? "CX" : chip.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: IslandStyle.subtextColor
                            }
                            // tiny remaining-quota bar, island-style
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 22
                                implicitHeight: 5
                                radius: 2.5
                                color: Qt.rgba(1, 1, 1, 0.15)
                                Rectangle {
                                    height: parent.height
                                    radius: 2.5
                                    width: parent.width * (AiUsage.saturated(chip.modelData) ? 1
                                           : Math.max(0, Math.min(1, (chip.modelData.remainingPct ?? 0) / 100)))
                                    color: AiUsage.chipColor(chip.modelData)
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                            StyledText {
                                text: AiUsage.remainingLabel(chip.modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: AiUsage.chipColor(chip.modelData)
                            }
                        }
                    }
                }

                // ---- voice assistant (Code) — replaces the assistant's own overlay ----
                Item {
                    id: assistantUI
                    // Top-anchored (not centred) so a tall wrapped text can't overflow
                    // past the notch's top edge — it grows DOWNWARD instead.
                    anchors.top: parent.top
                    anchors.topMargin: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "assistant" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    readonly property bool showBars: VoiceAssistant.mode === "bars" || VoiceAssistant.mode === "idle"
                    implicitWidth: assistantUI.showBars ? barsRow.implicitWidth : assistantText.width
                    implicitHeight: assistantUI.showBars ? 24 : assistantText.paintedHeight

                    property real idlePhase: 0
                    Timer {
                        running: VoiceAssistant.mode === "idle" && assistantUI.visible
                        interval: 30; repeat: true
                        onTriggered: assistantUI.idlePhase = (assistantUI.idlePhase + 0.06) % (2 * Math.PI)
                    }

                    Row {
                        id: barsRow
                        anchors.centerIn: parent
                        visible: assistantUI.showBars
                        spacing: 4
                        readonly property int barCount: 13
                        Repeater {
                            model: barsRow.barCount
                            Rectangle {
                                required property int index
                                width: 4
                                radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property real bh: {
                                    if (VoiceAssistant.mode === "idle")
                                        return Math.max(2, Math.abs(Math.sin(assistantUI.idlePhase + index * 0.7)) * 20);
                                    const dist = Math.sin((index / (barsRow.barCount - 1)) * Math.PI);
                                    return Math.max(2, VoiceAssistant.level * dist * 20);
                                }
                                height: bh
                                // cyan → violet as the bar grows (voice-assistant identity)
                                color: {
                                    const t = Math.min(1, bh / 20);
                                    return Qt.rgba(0.53 * t, 0.80 - 0.53 * t, 1, 1);
                                }
                                Behavior on height { SmoothedAnimation { velocity: 200 } }
                            }
                        }
                    }
                    // Natural (unwrapped) text width, measured independently so binding
                    // `width` to it can't loop.
                    TextMetrics {
                        id: assistantTextMetrics
                        font: assistantText.font
                        text: VoiceAssistant.text
                    }
                    StyledText {
                        id: assistantText
                        anchors.centerIn: parent
                        visible: VoiceAssistant.mode === "text"
                        text: VoiceAssistant.text
                        color: IslandStyle.textColor
                        font.pixelSize: Appearance.font.pixelSize.small
                        horizontalAlignment: Text.AlignHCenter
                        // One line while it fits; once it hits the cap it wraps by word
                        // and the notch grows DOWN (see implicitHeight + targetHeight).
                        wrapMode: Text.WordWrap
                        width: Math.min(assistantTextMetrics.advanceWidth + 2, root.expandedMaxWidth - 40)
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                }

                // ---- brightness ----
                RowLayout {
                    id: brightnessUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "brightness" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 20
                        fill: 1
                        color: IslandStyle.textColor
                        text: (notchWindow.brightnessMonitor?.brightness ?? 1) < 0.5 ? "brightness_low" : "brightness_high"
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
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "notification" ? 1 : 0
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

                // ---- charging: bolt + percentage (plug/unplug morph) ----
                RowLayout {
                    id: chargingUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "charging" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        text: Battery.isPluggedIn ? "bolt" : "battery_android_full"
                        fill: 1
                        iconSize: 20
                        color: Battery.isPluggedIn ? "#7EE787" : IslandStyle.textColor
                    }
                    StyledText {
                        text: `${Math.round(Battery.percentage * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: IslandStyle.textColor
                    }
                    StyledText {
                        text: Battery.isPluggedIn ? Translation.tr("Charging") : Translation.tr("On battery")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: IslandStyle.subtextColor
                    }
                }

                // ---- btdevice: freshly connected device, AirPods-style ----
                RowLayout {
                    id: btUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "btdevice" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        text: Icons.getBluetoothDeviceMaterialSymbol(root.btMorphDevice?.icon ?? "")
                        fill: 1
                        iconSize: 19
                        color: IslandStyle.accent
                    }
                    StyledText {
                        Layout.maximumWidth: 190
                        text: root.btMorphDevice?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: IslandStyle.textColor
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: root.btMorphDevice?.batteryAvailable ?? false
                        text: `${Math.round((root.btMorphDevice?.battery ?? 0) * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: IslandStyle.subtextColor
                    }
                }

                // ---- welcome: short greeting after unlocking ----
                RowLayout {
                    id: welcomeUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "welcome" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        text: "waving_hand"
                        fill: 1
                        iconSize: 19
                        color: IslandStyle.accent
                    }
                    StyledText {
                        text: `${Translation.tr("Welcome back")}, ${SystemInfo.username}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: IslandStyle.textColor
                    }
                }

                // ---- pomodoro: countdown while the focus timer runs ----
                RowLayout {
                    id: pomodoroUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "pomodoro" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        text: Pomodoro.phase === "work" ? "timer" : "coffee"
                        fill: 1
                        iconSize: 19
                        color: Pomodoro.phase === "work" ? IslandStyle.accent : "#7EE787"
                    }
                    StyledText {
                        text: Pomodoro.display
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: IslandStyle.textColor
                    }
                    StyledText {
                        text: Pomodoro.phase === "work" ? Translation.tr("Focus") : Translation.tr("Break")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: IslandStyle.subtextColor
                    }
                }

                // ---- locked: padlock + Locked (no media available) ----
                RowLayout {
                    id: lockUI
                    anchors.centerIn: parent
                    spacing: 9
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "locked" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MaterialSymbol {
                        text: "lock"
                        fill: 1
                        iconSize: 17
                        color: IslandStyle.textColor
                    }
                    StyledText {
                        text: Translation.tr("Locked")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: IslandStyle.textColor
                    }
                }

                // ---- media: THE shared notch media row (also above the lock) ----
                NotchMediaRow {
                    id: mediaUI
                    anchors.centerIn: parent
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "media" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                }

                // ---- agent (compact): pixel mascot + status ----
                RowLayout {
                    id: agentUI
                    anchors.fill: parent
                    anchors.leftMargin: 16   // breathing room to the LEFT of the mascot
                    anchors.rightMargin: 14 + notchWindow.privacyPad // dots get their own zone
                    spacing: 11              // gap between the mascot cluster and the text area
                    opacity: notchWindow.islandState === "expanded" && notchWindow.displaySource === "agent" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    AgentSpinner {
                        Layout.alignment: Qt.AlignVCenter
                        // resting presence → green "running" mascot (alive, no bars)
                        mode: AgentService.headlineMode === "idle" ? "running" : (AgentService.headlineMode === "" ? "idle" : AgentService.headlineMode)
                        pixel: 2
                    }
                    // Fills the remaining estate; status text centered IN it (true
                    // midpoint of the right-hand space). Count rides the far right.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        AgentStatusText {
                            anchors.centerIn: parent
                            readonly property string m: AgentService.headlineMode
                            readonly property string t: AgentService.toast
                            word: t !== "" ? t
                                : m === "permission" ? "Needs you" : m === "waiting" ? "Waiting"
                                : m === "working" ? "Working" : m === "done" ? "Done" : "Agent Island"
                            animateDots: t === "" && (m === "working" || m === "waiting")
                            shimmer: t === "" && (m === "working" || m === "waiting" || m === "permission")
                            baseColor: (t !== "" || m === "done") ? "#7EE787" : IslandStyle.textColor
                            pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: AgentService.sessionCount > 1
                            text: AgentService.sessionCount
                            color: IslandStyle.subtextColor
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    // now-playing indicator — coexists when media plays while an agent is active
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.mediaActive
                        implicitWidth: 20
                        implicitHeight: 20
                        Rectangle { anchors.fill: parent; radius: 5; color: Qt.rgba(1, 1, 1, 0.08) }
                        StyledImage {
                            id: miniArt
                            anchors.fill: parent
                            source: CoverArt.displayedArt
                            fillMode: Image.PreserveAspectCrop
                            visible: CoverArt.displayedArt !== "" && status === Image.Ready
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: miniArt.width; height: miniArt.height; radius: 5 }
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !miniArt.visible
                            text: "music_note"
                            iconSize: 13
                            color: IslandStyle.subtextColor
                        }
                    }
                }

                // ---- privacy dots (macOS-style): mic = orange, screencast = green ----
                Row {
                    id: privacyDots
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    visible: notchWindow.islandState !== "open" && (PrivacyIndicators.micActive || PrivacyIndicators.screensharing)

                    HoverHandler { id: privacyHover }

                    Rectangle {
                        visible: PrivacyIndicators.micActive
                        width: 7
                        height: 7
                        radius: 3.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#FF9F0A"
                    }
                    Rectangle {
                        visible: PrivacyIndicators.screensharing
                        width: 7
                        height: 7
                        radius: 3.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#32D74B"
                    }

                    IslandPopup {
                        anchorItem: privacyDots
                        shouldShow: privacyHover.hovered
                        contentComponent: Component {
                            Column {
                                spacing: 4
                                StyledText {
                                    visible: PrivacyIndicators.micActive
                                    text: Translation.tr("Microphone:") + " " + PrivacyIndicators.micApps.join(", ")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: "#FF9F0A"
                                }
                                StyledText {
                                    visible: PrivacyIndicators.screensharing
                                    text: Translation.tr("Screen is being shared")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: "#32D74B"
                                }
                            }
                        }
                    }
                }

                // ---- open-state surface host (dashboard / power / tools / launcher / overview) ----
                FocusScope {
                    id: surfaceHost
                    anchors.fill: parent
                    visible: notchWindow.islandState === "open"
                    focus: visible
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

                    // Absorb clicks on empty surface padding so they don't fall through
                    // to the notch background (which would close the surface).
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                    }

                    Loader {
                        id: surfaceLoader
                        anchors.fill: parent
                        active: surfaceHost.visible
                        focus: true
                        sourceComponent: {
                            switch (Island.openSurface) {
                            case "dashboard":
                                return dashboardComp;
                            case "power":
                                return powerComp;
                            case "tools":
                                return toolsComp;
                            case "launcher":
                                return launcherComp;
                            case "overview":
                                return overviewComp;
                            case "agent":
                                return agentComp;
                            case "wallpapers":
                                return wallpapersComp;
                            default:
                                return null;
                            }
                        }
                    }
                    Component { id: dashboardComp; DashboardSurface { focus: true } }
                    Component { id: powerComp; PowerSurface { focus: true } }
                    Component { id: toolsComp; ToolsSurface { focus: true } }
                    Component { id: launcherComp; LauncherSurface { focus: true } }
                    Component { id: overviewComp; OverviewSurface { focus: true } }
                    Component { id: agentComp; AgentSurface { focus: true } }
                    Component { id: wallpapersComp; WallpaperSelectorContent { focus: true; onDismissed: Island.close() } }
                }
            }
        }
    }

    // Dedicated top-strip reservation. A stable, empty, full-width, click-through
    // window that reserves `reservedStrip` px at the top so maximized windows open
    // BELOW the island row (like the bar used to). Kept SEPARATE from the notch
    // window — the notch is full-screen (all-4-anchored) so its click-anywhere
    // catcher works, which would forfeit exclusiveZone; this tiny strip carries the
    // reservation instead, and never resizes so windows never jump.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "quickshell:islandReserve"
            WlrLayershell.layer: WlrLayer.Bottom
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.reservedStrip
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: root.reservedStrip
            mask: Region {}   // fully click-through — purely a spacer
        }
    }

    // Small reusable OSD bits.
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
