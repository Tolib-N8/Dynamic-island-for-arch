#!/usr/bin/env python3
"""
OpenAgentIsland — notification mirror (Plasma edition).

On KDE Plasma, plasmashell owns the org.freedesktop.Notifications D-Bus service,
so the notch's own notification server can't register. Instead of fighting for
the name (which would disable KDE's native notifications), we *mirror*: become a
passive D-Bus monitor, watch every `Notify` call, and forward a compact JSON line
to the notch over a Unix socket. KDE keeps showing notifications normally; the
notch shows them too.

Fire-and-forget, exactly like the agent hook (bridge/oai_hook.py): each notice is
an independent short-lived connection, so it survives the notch restarting and
never blocks the desktop. If the notch isn't listening, the notice is dropped.

Single-instance via an abstract-namespace lock socket so relaunching is safe.

Run:  python3 notif_bridge.py           # mirror to the notch
      python3 notif_bridge.py --print   # debug: print to stdout, don't forward
"""
import json
import os
import socket
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

PRINT_ONLY = "--print" in sys.argv


def notif_socket():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(base, "openagentisland-notif.sock")


def single_instance_or_exit():
    # Bind an abstract-namespace socket (Linux); fails if another copy holds it.
    global _lock
    _lock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        _lock.bind("\0openagentisland-notif-bridge")
    except OSError:
        sys.stderr.write("notif_bridge: already running\n")
        sys.exit(0)


def forward(payload):
    line = (json.dumps(payload) + "\n").encode()
    if PRINT_ONLY:
        sys.stdout.write(line.decode())
        sys.stdout.flush()
        return
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.25)
        s.connect(notif_socket())
        s.sendall(line)
        s.close()
    except Exception:
        pass  # notch down → drop, never block


def handler(bus, msg):
    try:
        if msg.get_interface() != "org.freedesktop.Notifications":
            return
        if msg.get_member() != "Notify":
            return
        args = list(msg.get_args_list())
        # Notify(app_name, replaces_id, app_icon, summary, body, actions, hints, timeout)
        app_name = str(args[0]) if len(args) > 0 else ""
        app_icon = str(args[2]) if len(args) > 2 else ""
        summary = str(args[3]) if len(args) > 3 else ""
        body = str(args[4]) if len(args) > 4 else ""
        hints = args[6] if len(args) > 6 else {}
        # desktop-entry hint is a better icon hint than app_icon for many apps
        desktop_entry = ""
        try:
            desktop_entry = str(hints.get("desktop-entry", ""))
        except Exception:
            pass
        if not summary and not body:
            return  # nothing to show
        forward({
            "type": "notification",
            "appName": app_name,
            "appIcon": app_icon,
            "desktopEntry": desktop_entry,
            "summary": summary,
            "body": body,
        })
    except Exception:
        return  # never let a bad message kill the monitor


def main():
    single_instance_or_exit()
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    # Become a passive monitor for Notify calls (non-invasive; doesn't own the name).
    bus.call_blocking(
        "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus.Monitoring", "BecomeMonitor", "asu",
        ([f"interface='org.freedesktop.Notifications',member='Notify'"], dbus.UInt32(0)),
    )
    bus.add_message_filter(handler)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
