pragma Singleton
import QtQuick
import Quickshell

// Shared "bus" so pills on the side islands (separate PanelWindows) can command
// the centre notch to open a named surface in its `open` state. Mirrors the
// reference's notch.stack + open_notch(name) / close_notch().
//
// openSurface: "" = closed; else one of dashboard | power | tools | launcher | overview
Singleton {
    id: root

    property string openSurface: ""

    function open(name) {
        root.openSurface = name;
    }
    function close() {
        root.openSurface = "";
    }
    function toggle(name) {
        root.openSurface = (root.openSurface === name) ? "" : name;
    }
}
