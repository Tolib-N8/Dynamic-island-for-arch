// OpenAgentIsland global shortcuts — run INSIDE KWin, the same mechanism as
// built-in shortcuts, so they work regardless of kglobalaccel service quirks
// (dynamically registered .desktop service shortcuts stay inactive until the
// next login; KWin script shortcuts bind immediately and on every start).
//
// KWin scripts can't spawn processes; StartUnit on a oneshot systemd user
// unit is the DBus-only way to run `qs ipc ...`.

registerShortcut("OAI Island Clipboard", "Island Clipboard (OpenAgentIsland)", "Meta+V", function () {
    callDBus("org.freedesktop.systemd1", "/org/freedesktop/systemd1",
             "org.freedesktop.systemd1.Manager", "StartUnit",
             "oai-clipboard.service", "replace");
});
