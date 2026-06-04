#!/usr/bin/env python3
"""
Mock island listener — for testing the hook bridge WITHOUT Quickshell.

Listens on the island socket, prints every event it receives, and answers
permission_requests according to a mode:
    allow  — respond allow
    deny   — respond deny
    ask    — respond {"decision":"ask"} (hook should fall back to normal prompt)
    hang   — never respond (simulate a frozen island; hook must time out safely)

Usage: mock_listener.py [allow|deny|ask|hang]   (default allow)
"""
import json
import os
import socket
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "allow"


def socket_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(base, "openagentisland.sock")


path = socket_path()
try:
    os.unlink(path)
except FileNotFoundError:
    pass

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(16)
print(f"[mock] listening on {path} mode={mode}", flush=True)

hung = []  # keep frozen connections referenced so they stay open

while True:
    try:
        conn, _ = srv.accept()
    except KeyboardInterrupt:
        break
    data = b""
    while b"\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
    line = data.split(b"\n", 1)[0].decode().strip()
    try:
        msg = json.loads(line)
    except Exception:
        msg = {"raw": line}
    print(f"[mock] recv: {json.dumps(msg)}", flush=True)

    if msg.get("type") == "permission_request":
        if mode == "hang":
            hung.append(conn)  # never respond; keep open
            continue
        if mode in ("allow", "deny"):
            resp = {"type": "permission_decision",
                    "request_id": msg.get("request_id", ""),
                    "decision": mode}
        else:  # ask
            resp = {"decision": "ask"}
        try:
            conn.sendall((json.dumps(resp) + "\n").encode())
        except Exception:
            pass
    conn.close()
