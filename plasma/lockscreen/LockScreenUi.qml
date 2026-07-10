/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                // OpenAgentIsland unlock animation: quick exit morph, then quit.
                // unlockSafetyTimer guarantees quit even if the animation stalls.
                unlockSafetyTimer.start();
                unlockExitAnim.start();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    // ---- OpenAgentIsland unlock animation ----
    // Seamless handoff: the clock pill shrinks back into the desktop notch's idle
    // geometry (same spot, same size) while the rest of the UI fades out via the
    // stock WallpaperFader (uiVisible=false) — no competing animations. When the
    // lock surface then disappears, the real desktop notch is sitting exactly
    // where the pill just was, so the eye tracks one continuous notch.
    SequentialAnimation {
        id: unlockExitAnim
        ScriptAction { script: lockScreenRoot.uiVisible = false }  // stock fade for auth UI/footer
        ParallelAnimation {
            NumberAnimation {
                target: islandNotch; property: "width"
                to: islandNotch.idleW
                duration: 300
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: islandNotch; property: "height"
                to: islandNotch.idleH
                duration: 300
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: notchContent; property: "opacity"
                to: 0
                duration: 180
                easing.type: Easing.OutQuad
            }
        }
        PauseAnimation { duration: 50 }
        ScriptAction { script: Qt.quit() }
    }
    // Unlocking must never hang on a stuck animation: hard-quit shortly after.
    Timer {
        id: unlockSafetyTimer
        interval: 800
        onTriggered: Qt.quit()
    }

    MouseArea {
        id: lockScreenRoot

        // OpenAgentIsland: start INVISIBLE. Without this, the first frame(s)
        // between the window mapping and launchAnimation's first tick render at
        // the default opacity 1 — a bright full-UI flash, then a jump to black,
        // then the fade ("blinking"). launchAnimation still fades 0 → 1.
        opacity: 0

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (inputPanel.keyboardActive) {
                    inputPanel.showHide();
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    mainBlock.mainPasswordBox.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            // OpenAgentIsland: unhurried fade-in from the compositor's security
            // blackout, so the black moment reads as the START of the lock
            // choreography (dark → wallpaper blooms → notch grows) instead of a
            // glitch. The notch pill starts at the desktop notch's exact geometry,
            // so it overlays the identical desktop pill as it fades in.
            duration: 550
            easing.type: Easing.OutQuad
        }

        Component.onCompleted: launchAnimation.start();

        WallpaperFader {
            anchors.fill: parent
            state: lockScreenRoot.uiVisible ? "on" : "off"
            source: wallpaper
            mainStack: mainStack
            footer: footer
            clock: clock
            alwaysShowClock: config.alwaysShowClock && !config.hideClockWhenIdle
        }

        // ---- OpenAgentIsland: concave shoulders — the pill flows into the top edge
        // exactly like the desktop island (they ride the pill's edges during morphs).
        NotchShoulder {
            leftSide: true
            size: 20
            anchors.right: islandNotch.left
            anchors.rightMargin: -1
            anchors.top: parent.top
            z: islandNotch.z
        }
        NotchShoulder {
            leftSide: false
            size: 20
            anchors.left: islandNotch.right
            anchors.leftMargin: -1
            anchors.top: parent.top
            z: islandNotch.z
        }

        // ---- OpenAgentIsland: notch-style clock pill, top-center like the island ----
        // Seamless handoff with the desktop island: the pill starts (on lock) and
        // ends (on unlock) at the EXACT geometry of the desktop notch's idle pill
        // (180×36, radius 18, flush top-center) — so locking reads as the desktop
        // notch growing into the clock, and unlocking as it shrinking back into
        // the very notch that is revealed when the lock surface goes away.
        Rectangle {
            id: islandNotch
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real idleW: 180   // keep in sync with IslandNotch idle
            readonly property real idleH: 36
            // Full pill must be clearly WIDER than idle so the morph grows in both
            // axes (the date line can be narrower than 180px).
            readonly property real fullW: Math.max(idleW + 72, notchContent.implicitWidth + 64)
            readonly property real fullH: notchContent.implicitHeight + 24
            width: idleW
            height: idleH
            color: "#000000"
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: 18
            bottomRightRadius: 18
            z: 10

            // Lock (entrance): grow from the desktop notch's idle pill into the
            // clock with the island's goey overshoot; content fades in en route.
            Component.onCompleted: notchEntrance.start()
            SequentialAnimation {
                id: notchEntrance
                // Hold the idle pill through the surface fade-in (launchAnimation,
                // 550ms) so it visually IS the desktop notch, then grow.
                PauseAnimation { duration: 470 }
                ParallelAnimation {
                    NumberAnimation {
                        target: islandNotch; property: "width"
                        from: islandNotch.idleW; to: islandNotch.fullW
                        duration: 480
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.34, 1.22, 0.64, 1, 1, 1]
                    }
                    NumberAnimation {
                        target: islandNotch; property: "height"
                        from: islandNotch.idleH; to: islandNotch.fullH
                        duration: 480
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.34, 1.22, 0.64, 1, 1, 1]
                    }
                    NumberAnimation {
                        target: notchContent; property: "opacity"
                        from: 0; to: 1
                        duration: 320
                        easing.type: Easing.OutQuad
                    }
                }
                // Re-bind so the pill keeps tracking content size (date changes etc.)
                ScriptAction {
                    script: {
                        islandNotch.width = Qt.binding(() => islandNotch.fullW);
                        islandNotch.height = Qt.binding(() => islandNotch.fullH);
                    }
                }
            }

            property date now: new Date()
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: islandNotch.now = new Date()
            }

            ColumnLayout {
                id: notchContent
                anchors.centerIn: parent
                spacing: 0
                opacity: 0   // fades in with the entrance morph

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: islandNotch.now.toLocaleTimeString(Qt.locale(), "h:mm")
                    color: "#FFFFFF"
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: islandNotch.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                    color: "#9AA0AA"
                    font.pixelSize: 12
                }
            }
        }

        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            visible: false // OpenAgentIsland: replaced by the notch clock pill
            radius: 7
            verticalOffset: 0.8
            samples: 15
            spread: 0.2
            color : Qt.rgba(0, 0, 0, 0.7)
            opacity: lockScreenRoot.uiVisible ? 0 : 1
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration * 2
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Clock {
            id: clock
            property Item shadow: clockShadow
            visible: false // OpenAgentIsland: replaced by the notch clock pill
            anchors.horizontalCenter: parent.horizontalCenter
            y: (mainBlock.userList.y + mainStack.y)/2 - height/2
            Layout.alignment: Qt.AlignBaseline
        }

        ListModel {
            id: users

            Component.onCompleted: {
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
            }
        }

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0

            initialItem: MainBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible

                showUserList: userList.y + mainStack.y > 0

                enabled: !graceLockTimer.running

                StackView.onStatusChanged: {
                    // prepare for presenting again to the user
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                    }
                }
                userListModel: users


                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    authenticator.respond(password)
                }

                actionItems: [
                    ActionButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Slee&p")
                        icon.name: "system-suspend"
                        onClicked: sessionManagement.suspend()
                        visible: sessionManagement.canSuspend
                    },
                    ActionButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "&Hibernate")
                        icon.name: "system-suspend-hibernate"
                        onClicked: sessionManagement.hibernate()
                        visible: sessionManagement.canHibernate
                    },
                    ActionButton {
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Switch &User")
                        icon.name: "system-switch-user"
                        onClicked: {
                            sessionManagement.switchUser();
                        }
                        visible: sessionManagement.canSwitchUser
                    }
                ]

                Loader {
                    Layout.topMargin: Kirigami.Units.smallSpacing // some distance to the password field
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    active: config.showMediaControls
                    source: "MediaControls.qml"
                }
            }
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: lockScreenRoot
            mainStack: mainStack
            mainBlock: mainBlock
            passwordField: mainBlock.mainPasswordBox
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        // Note: Containment masks stretch clickable area of their buttons to
        // the screen edges, essentially making them adhere to Fitts's law.
        // Due to virtual keyboard button having an icon, buttons may have
        // different heights, so fillHeight is required.
        //
        // Note for contributors: Keep this in sync with SDDM Main.qml footer.
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton

                focusPolicy: Qt.TabFocus
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: inputPanel.keyboardActive ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                onClicked: {
                    // Otherwise the password field loses focus and virtual keyboard
                    // keystrokes get eaten
                    mainBlock.mainPasswordBox.forceActiveFocus();
                    inputPanel.showHide()
                }

                visible: inputPanel.status === Loader.Ready

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: virtualKeyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            PlasmaComponents3.ToolButton {
                id: keyboardButton

                focusPolicy: Qt.TabFocus
                Accessible.description: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout")
                icon.name: "input-keyboard"

                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher

                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }

                text: keyboardLayoutSwitcher.layoutNames.longName
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()

                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: keyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: virtualKeyboardButton.visible ? 0 : -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Battery {}
        }
    }
}
