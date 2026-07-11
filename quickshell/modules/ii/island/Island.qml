pragma Singleton
import QtQuick
import Quickshell

// Shared "bus" so pills on the side islands (separate PanelWindows) can command
// the centre notch to open a named surface in its `open` state. Mirrors the
// reference's notch.stack + open_notch(name) / close_notch().
//
// openSurface: "" = closed; else one of dashboard | power | tools | launcher | overview
// openScreen:  name of the monitor that owns the open surface ("" while closed).
//   Only ONE monitor shows a surface at a time — opening on another moves it there,
//   so clicking an island opens it on THAT screen, not on all of them.
Singleton {
    id: root

    property string openSurface: ""
    property string openScreen: ""
    // Set while a surface needs real keyboard input (e.g. the Wi-Fi password
    // prompt). On KWin the notch normally refuses keyboard focus (Meta+Q would
    // close it as the "active window"); this narrowly re-enables it.
    property bool wantsKeyboard: false
    // True when the surface opened itself (agent permission request) rather than
    // by a user click. Auto-opened surfaces must NOT hijack the screen: the notch
    // stays interactive but everything outside remains click-through, so the user
    // can keep working while a permission card waits.
    property bool autoOpened: false

    function open(name, screen, auto) {
        root.openSurface = name;
        root.openScreen = screen || "";
        root.autoOpened = !!auto;
    }
    function close() {
        root.openSurface = "";
        root.openScreen = "";
        root.wantsKeyboard = false;
        root.autoOpened = false;
    }
    function toggle(name, screen) {
        const s = screen || "";
        if (root.openSurface === name && root.openScreen === s)
            root.close();
        else
            root.open(name, s);
    }
}
