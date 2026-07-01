pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Receives notifications mirrored from the desktop's real notification server by
// bridge/notif_bridge.py (used on Plasma, where plasmashell owns
// org.freedesktop.Notifications and the notch can't be the server itself).
//
// Passive + defensive: every parse is guarded; a flood is capped. On Hyprland this
// service simply stays empty (no bridge runs — the built-in Notifications service
// is the real server there), so it's harmless to reference everywhere.
Singleton {
    id: root

    readonly property string socketPath: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        return (xdg && xdg.length > 0 ? xdg : "/tmp") + "/openagentisland-notif.sock";
    }
    readonly property int maxItems: 20

    // [{ id, appName, appIcon, desktopEntry, summary, body, ts }] — newest first
    property var list: []
    property int _nextId: 1

    signal notified(var notif)

    function _push(obj) {
        const n = {
            "id": root._nextId++,
            "appName": obj.appName || "",
            "appIcon": obj.appIcon || "",
            "desktopEntry": obj.desktopEntry || "",
            "summary": obj.summary || "",
            "body": obj.body || "",
            "ts": Math.floor(Date.now() / 1000)
        };
        const next = [n].concat(root.list);
        if (next.length > root.maxItems)
            next.length = root.maxItems;
        root.list = next;
        root.notified(n);
    }

    function dismiss(id) {
        root.list = root.list.filter(x => x.id !== id);
    }
    function clear() {
        root.list = [];
    }

    function onLine(line) {
        if (!line || line.trim().length === 0)
            return;
        let obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (obj && obj.type === "notification")
            root._push(obj);
    }

    SocketServer {
        active: true
        path: root.socketPath
        handler: Component {
            Socket {
                parser: SplitParser {
                    onRead: line => root.onLine(line)
                }
            }
        }
    }
}
