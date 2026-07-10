pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// CodexBar-style AI quota tracker: how much of each AI platform's rate limit
// remains. Polls scripts/ai/usage_poll.py, which reads Codex CLI's exact
// subscription snapshots (~/.codex/sessions rate_limits events) and estimates
// the Claude Code 5h block via ccusage (marked estimate). See that script for
// the JSON schema.
Singleton {
    id: root

    // [{ id, label, usedPct, remainingPct, resetsAt, windowMinutes, plan, estimate, detail }]
    property var providers: []
    property double lastUpdated: 0
    readonly property bool available: providers.length > 0

    function provider(id) {
        for (let i = 0; i < root.providers.length; i++)
            if (root.providers[i].id === id)
                return root.providers[i];
        return null;
    }

    // remaining-quota color ramp: plenty → green, mid → orange, low → red
    function levelColor(remaining) {
        if (remaining === null || remaining === undefined)
            return "#9AA0AA";
        return remaining <= 15 ? "#E05561" : remaining <= 40 ? "#E8A23D" : "#7EE787";
    }

    // Estimated ceilings (Claude) saturate when the current block outgrows the
    // historical max — that's "you're in record territory", not a hard cutoff.
    function saturated(p) {
        return p && p.estimate && p.remainingPct !== null && p.remainingPct !== undefined && p.remainingPct <= 0;
    }
    function remainingLabel(p) {
        if (!p || p.remainingPct === null || p.remainingPct === undefined)
            return "—";
        if (saturated(p))
            return "at max";
        return Math.round(p.remainingPct) + "%";
    }
    function chipColor(p) {
        return saturated(p) ? "#E8A23D" : levelColor(p ? p.remainingPct : null);
    }

    function resetIn(p) {
        if (!p || !p.resetsAt)
            return "";
        const s = p.resetsAt - Date.now() / 1000;
        if (s <= 0)
            return "now";
        if (s < 5400)
            return Math.max(1, Math.round(s / 60)) + "m";
        if (s < 129600)
            return Math.round(s / 3600) + "h";
        return Math.round(s / 86400) + "d";
    }

    function refresh() {
        if (!pollProc.running)
            pollProc.running = true;
    }

    // Warn (once per reset window) when a provider's remaining quota drops to
    // the red zone. Sent as a regular desktop notification — the notch is the
    // notification server, so it morphs like any other notification.
    property int warnThreshold: 15
    property var _warnedWindows: ({})

    function _maybeWarn() {
        const warned = root._warnedWindows;
        for (let i = 0; i < root.providers.length; i++) {
            const p = root.providers[i];
            if (p.remainingPct === null || p.remainingPct === undefined)
                continue;
            if (p.remainingPct > root.warnThreshold)
                continue;
            const key = p.id + ":" + (p.resetsAt ?? "na");
            if (warned[key])
                continue;
            warned[key] = true;
            const left = root.saturated(p) ? "at max" : Math.round(p.remainingPct) + "% left";
            Quickshell.execDetached(["notify-send", "-a", "AI Limits", "-i", "data_usage",
                `${p.label}: ${left}${p.estimate ? " (estimate)" : ""}`,
                `resets in ${root.resetIn(p) || "?"} · ${p.plan || ""}`]);
        }
        root._warnedWindows = warned;
    }

    Process {
        id: pollProc
        command: ["python3", `${Directories.scriptPath}/ai/usage_poll.py`.replace(/file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d && d.providers) {
                        root.providers = d.providers;
                        root.lastUpdated = Date.now();
                        root._maybeWarn();
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 90000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
