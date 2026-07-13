import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.island
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconBaseSize: 35
    property real iconSize: iconBaseSize * magFactor
    property real countDotWidth: 5
    property real countDotHeight: 5
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator

    // --- macOS-style magnification -------------------------------------------
    // Icons swell as the cursor nears (cosine falloff). Centre uses the BASE
    // width, not the live one — the live width depends on magFactor and would
    // bind in a loop.
    readonly property real magBase: implicitHeight - topInset - bottomInset
    readonly property real magRange: 96
    readonly property real magBoost: 0.6
    readonly property real magFactor: {
        if (!appListRoot.magnifyOn || root.isSeparator)
            return 1;
        const d = Math.abs(root.x + root.magBase / 2 - appListRoot.cursorX);
        if (d >= root.magRange)
            return 1;
        return 1 + root.magBoost * (0.5 + 0.5 * Math.cos(Math.PI * d / root.magRange));
    }
    implicitWidth: isSeparator ? 1 : magBase * magFactor
    Behavior on implicitWidth {
        enabled: !root.isSeparator
        NumberAnimation { duration: 70 }
    }

    // --- launch bounce ---------------------------------------------------------
    property real bounceY: 0
    transform: Translate { y: root.bounceY }
    SequentialAnimation {
        id: launchBounce
        NumberAnimation { target: root; property: "bounceY"; to: -16; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bounceY"; to: 0; duration: 180; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "bounceY"; to: -8; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bounceY"; to: 0; duration: 150; easing.type: Easing.InQuad }
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            launchBounce.restart();
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        root.desktopEntry?.execute();
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent
            // Swell upward from a fixed bottom edge, macOS-style.
            transform: Translate { y: -(root.iconSize - root.iconBaseSize) / 2 }

            // Light glass tile behind every icon — dark icons (kitty, zen,
            // Yandex Music) were invisible against the near-black dock.
            Rectangle {
                anchors.centerIn: iconImageLoader
                width: root.iconSize + 9
                height: root.iconSize + 9
                radius: width * 0.28
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.07)
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: root.countDotWidth
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? IslandStyle.accent : Qt.rgba(1, 1, 1, 0.35)
                    }
                }
            }
        }
    }
}
