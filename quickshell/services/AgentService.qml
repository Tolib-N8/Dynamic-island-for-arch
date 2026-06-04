pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Headless listener for the Claude Code agent bridge. Hosts the Unix socket that
// the hook client (bridge/oai_hook.py) connects to. Maintains per-session status
// and a queue of pending permission requests, and writes Allow/Deny decisions
// back on the held connection. The notch agent UI (later) reads `sessions` /
// `pendingPermissions` and calls allow()/deny(). See bridge/ + NOTES.md §5.
//
// Safety lives on the HOOK side (timeout + fallback). This side just needs to not
// crash on bad input — every parse is guarded; a dropped connection clears its
// pending request so the queue can't wedge.
Singleton {
    id: root

    readonly property string socketPath: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        return (xdg && xdg.length > 0 ? xdg : "/tmp") + "/openagentisland.sock";
    }
    property bool debug: true

    // session_id → { project, cwd, tool, summary, message, lastEvent, status, ts }
    property var sessions: ({})
    // [{ request_id, session_id, project, cwd, tool, summary, ts }]
    property var pendingPermissions: []
    property var _conns: ({})  // request_id → Socket (held open until decided)

    // no-op so shell.qml can force-instantiate this singleton (→ server goes active)
    function load() {}

    function statusFor(event, prev) {
        switch (event) {
        case "SessionStart": return "idle";
        case "UserPromptSubmit": return "running";
        case "PreToolUse": return "running";
        case "PostToolUse": return "running";
        case "Notification": return "waiting";
        case "Stop": return "idle";
        default: return prev || "idle";
        }
    }

    function applyEvent(obj) {
        const sid = obj.session_id || "default";
        const prev = root.sessions[sid] || {};
        const next = Object.assign({}, root.sessions);
        next[sid] = {
            "project": obj.project || prev.project || "",
            "cwd": obj.cwd || prev.cwd || "",
            "tool": obj.tool || "",
            "summary": obj.summary || "",
            "message": obj.message || "",
            "lastEvent": obj.event || "",
            "status": statusFor(obj.event, prev.status),
            "ts": obj.ts || 0,
        };
        root.sessions = next;
    }

    function addPermission(obj, conn) {
        root._conns[obj.request_id] = conn;
        const list = root.pendingPermissions.slice();
        list.push({
            "request_id": obj.request_id,
            "session_id": obj.session_id || "",
            "project": obj.project || "",
            "cwd": obj.cwd || "",
            "tool": obj.tool || "",
            "summary": obj.summary || "",
            "ts": obj.ts || 0,
        });
        root.pendingPermissions = list;
        const sid = obj.session_id || "default";
        const prev = root.sessions[sid] || {};
        const next = Object.assign({}, root.sessions);
        next[sid] = Object.assign({}, prev, {
            "project": obj.project || prev.project || "",
            "cwd": obj.cwd || prev.cwd || "",
            "tool": obj.tool || "",
            "summary": obj.summary || "",
            "status": "permission",
        });
        root.sessions = next;
    }

    function dropPending(reqId) {
        delete root._conns[reqId];
        root.pendingPermissions = root.pendingPermissions.filter(p => p.request_id !== reqId);
    }

    function decide(reqId, decision, reason) {
        const conn = root._conns[reqId];
        if (conn) {
            try {
                conn.write(JSON.stringify({
                    "type": "permission_decision",
                    "request_id": reqId,
                    "decision": decision,
                    "reason": reason || "",
                }) + "\n");
                conn.flush();
            } catch (e) {}
        }
        dropPending(reqId);
    }
    function allow(reqId) { root.decide(reqId, "allow", ""); }
    function deny(reqId, reason) { root.decide(reqId, "deny", reason || "Denied from the island"); }

    function onLine(conn, line) {
        if (!line || line.trim().length === 0)
            return;
        if (root.debug)
            console.log("[agent] recv:", line);
        let obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (obj.type === "permission_request" && obj.request_id) {
            conn.reqId = obj.request_id;
            root.addPermission(obj, conn);
        } else {
            root.applyEvent(obj);
        }
    }

    // Manual control / test hook: `qs -c openagentisland ipc call agent <fn>`.
    // Acts on the oldest pending permission. Useful for testing the round-trip
    // and as a keyboard-free fallback.
    IpcHandler {
        target: "agent"
        function status(): string {
            return JSON.stringify({
                "sessions": Object.keys(root.sessions).length,
                "pending": root.pendingPermissions.length
            });
        }
        function allowOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.allow(r);
            return "allowed " + r;
        }
        function denyOldest(): string {
            if (root.pendingPermissions.length === 0)
                return "none";
            const r = root.pendingPermissions[0].request_id;
            root.deny(r, "Denied (ipc)");
            return "denied " + r;
        }
    }

    SocketServer {
        active: true
        path: root.socketPath
        handler: Component {
            Socket {
                id: conn
                property string reqId: ""
                parser: SplitParser {
                    onRead: line => root.onLine(conn, line)
                }
                onConnectedChanged: {
                    if (!conn.connected && conn.reqId.length > 0) {
                        root.dropPending(conn.reqId);
                        conn.reqId = "";
                    }
                }
            }
        }
    }
}
