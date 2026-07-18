import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Island wallpaper picker — an iOS-style filmstrip. Big previews scroll
// horizontally, the centred one swells; click the centre to apply (switchwall
// re-themes everything), click a neighbour to bring it to the centre.
FocusScope {
    id: root
    focus: true
    Keys.onEscapePressed: Island.close()
    // Arrow navigation + Enter to apply.
    Keys.onLeftPressed: strip.decrementCurrentIndex()
    Keys.onRightPressed: strip.incrementCurrentIndex()
    Keys.onReturnPressed: root.applyCurrent()
    Keys.onEnterPressed: root.applyCurrent()

    function applyCurrent() {
        const p = Wallpapers.wallpapers[strip.currentIndex];
        if (p) {
            Wallpapers.apply(p);
            Island.close();
        }
    }

    readonly property int previewW: 300
    readonly property int previewH: 169

    // Open centred on the wallpaper that is currently set.
    Component.onCompleted: {
        root.forceActiveFocus();
        const cur = Config.options?.background.wallpaperPath ?? "";
        const idx = Wallpapers.wallpapers.indexOf(cur);
        if (idx >= 0)
            strip.currentIndex = idx;
    }

    readonly property string currentName: {
        const p = Wallpapers.wallpapers[strip.currentIndex] ?? "";
        return p.split("/").pop();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 12
        spacing: 8

        ListView {
            id: strip
            Layout.fillWidth: true
            Layout.preferredHeight: root.previewH + 22
            orientation: ListView.Horizontal
            model: Wallpapers.wallpapers
            spacing: 16
            clip: false
            cacheBuffer: root.previewW * 6

            // Centre-snap: the current item always sits mid-strip.
            preferredHighlightBegin: width / 2 - root.previewW / 2
            preferredHighlightEnd: width / 2 + root.previewW / 2
            highlightRangeMode: ListView.StrictlyEnforceRange
            snapMode: ListView.SnapOneItem
            highlightMoveDuration: 260

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (event.angleDelta.y < 0 || event.angleDelta.x < 0)
                        strip.incrementCurrentIndex();
                    else
                        strip.decrementCurrentIndex();
                }
            }

            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                width: root.previewW
                height: root.previewH
                anchors.verticalCenter: parent?.verticalCenter

                readonly property real dist: Math.abs(cell.x + cell.width / 2 - strip.contentX - strip.width / 2)
                readonly property bool centred: cell.index === strip.currentIndex
                scale: Math.max(0.80, 1.06 - dist / strip.width * 0.55)
                opacity: Math.max(0.45, 1 - dist / strip.width * 1.1)
                z: -dist

                Rectangle {
                    id: frame
                    anchors.fill: parent
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: cell.centred ? 2 : 1
                    border.color: cell.centred ? IslandStyle.accent : Qt.rgba(1, 1, 1, 0.10)
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Image {
                        id: img
                        anchors.fill: parent
                        anchors.margins: 2
                        source: Qt.resolvedUrl("file://" + cell.modelData)
                        sourceSize.width: 420
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: img.width
                                height: img.height
                                radius: 12
                            }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: img.status !== Image.Ready
                        text: "image"
                        iconSize: 32
                        color: IslandStyle.subtextColor
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (cell.centred) {
                            root.applyCurrent();
                        } else {
                            strip.currentIndex = cell.index;
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            spacing: 10

            StyledText {
                Layout.fillWidth: true
                text: root.currentName
                font.pixelSize: Appearance.font.pixelSize.small
                color: IslandStyle.textColor
                elide: Text.ElideMiddle
            }
            StyledText {
                text: `${strip.currentIndex + 1} / ${Wallpapers.wallpapers.length}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: IslandStyle.subtextColor
            }
            MaterialSymbol {
                text: "shuffle"
                iconSize: 18
                color: shuffleHover.hovered ? IslandStyle.accent : IslandStyle.subtextColor
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: shuffleHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.currentIndex = Math.floor(Math.random() * Wallpapers.wallpapers.length)
                }
            }
            MaterialSymbol {
                text: "check_circle"
                iconSize: 20
                fill: 1
                color: applyHover.hovered ? IslandStyle.accent : IslandStyle.textColor
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: applyHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyCurrent()
                }
            }
        }
    }
}
