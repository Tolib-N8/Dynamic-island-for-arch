import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.ii.island

Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            property bool reveal: root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated)

            anchors {
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: root.pinned ? implicitHeight - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut

            mask: Region {
                item: dockMouseArea
            }

            MouseArea {
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal ? 0 : Config.options?.dock.hoverToReveal ? (dockRoot.implicitHeight - Config.options.dock.hoverRegionHeight) : (dockRoot.implicitHeight + 1)
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth

                    HoverHandler {
                        id: dockHover
                        onPointChanged: dockApps.cursorX = dockApps.mapFromItem(dockHoverRegion, point.position.x, 0).x
                    }

                    Item { // Wrapper for the dock background
                        id: dockBackground
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }

                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        height: parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            // Glass is see-through — a full-strength shadow behind it
                            // reads as a dark smudge, not depth.
                            opacity: 0.35
                        }
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                            // Liquid glass: mostly transparent — Hyprland blurs what's
                            // behind (custom/rules.lua: blur + ignore_alpha 0.15 for
                            // quickshell:dock) — with a glossy top sheen and bright rim.
                            // Light frosted tint only — dark stops read as pitch black
                            // over the (dark) wallpaper corner behind the dock.
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.30) }
                                GradientStop { position: 0.5; color: Qt.rgba(0.88, 0.90, 0.97, 0.18) }
                                GradientStop { position: 1.0; color: Qt.rgba(0.78, 0.81, 0.92, 0.13) }
                            }
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.30)
                            radius: height / 2.6

                            // gloss: soft light pooling in the upper half of the glass
                            Rectangle {
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    margins: 2
                                }
                                height: parent.height * 0.42
                                radius: parent.radius - 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                }
                            }
                            // hairline top highlight — the "glass edge"
                            Rectangle {
                                anchors {
                                    top: parent.top
                                    topMargin: 1
                                    horizontalCenter: parent.horizontalCenter
                                }
                                width: parent.width - parent.radius * 1.2
                                height: 1
                                radius: 0.5
                                color: Qt.rgba(1, 1, 1, 0.30)
                            }
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            property real padding: 5

                            // Apps only — the pin and app-grid buttons were dropped
                            // for a clean macOS look (overview stays on Super).
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                                magnifyOn: dockHover.hovered
                            }
                        }
                    }
                }
            }
        }
    }
}
