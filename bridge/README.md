# bridge/ — OpenAgentIsland ↔ Claude Code agent bridge

Lets live Claude Code sessions appear in the notch, with **Allow/Deny permission
approval from the island**. Transport is a Unix domain socket.

```
Claude Code hook  ──(JSON over unix socket)──▶  Quickshell AgentService
   oai_hook.py                                  (services/AgentService.qml)
        ▲                                                 │
        └──────────── permission decision ◀───────────────┘
```

## Files
- **`oai_hook.py`** — the hook client Claude Code runs. Two modes:
  - `oai_hook.py status` — fire-and-forget event (SessionStart / UserPromptSubmit
    / PostToolUse / Notification / Stop). Never blocks.
  - `oai_hook.py permission` — PreToolUse: sends the request and **blocks** for an
    Allow/Deny decision from the island, with a timeout.
- **`mock_listener.py`** — a standalone fake island for testing without Quickshell
  (`allow|deny|ask|hang`).
- **`test_safety.py`** — the safety harness (run it: `python3 bridge/test_safety.py`).
- **`hooks.settings.json`** — the snippet to merge into `~/.claude/settings.json`
  to enable the bridge (NOT installed automatically — see below).

The island side is `quickshell/services/AgentService.qml` (a `SocketServer`).

## SAFETY — the rule that must never break
A blocking hook could hang real Claude Code if the island is down or frozen.
`oai_hook.py` guarantees it never does:
- **No socket / connect refused** → exit 0, no output → Claude uses its normal flow.
- **Permission timeout / frozen island** → hook returns after `OAI_PERMISSION_TIMEOUT`
  (default 20s) → exit 0, no output → Claude falls back to its **normal permission
  prompt**. It never auto-approves on failure.
- **Any exception** → exit 0 backstop.
- Claude Code's own per-hook `timeout` is a second net.

`test_safety.py` proves all of this (listener down, allow, deny, frozen,
delivery) — 13/13 checks. Run it after any change to the hook.

The island also drops a pending request if the hook disconnects, so a timed-out
request can't wedge the queue.

## Socket + wire protocol
- Path: `$XDG_RUNTIME_DIR/openagentisland.sock` (fallback `/tmp/openagentisland.sock`).
- Newline-delimited JSON, one message per connection.
- **Event** (hook→island, fire-and-forget):
  `{"type":"event","event":"PostToolUse","session_id":"…","cwd":"…","project":"…","tool":"Bash","summary":"…","message":"…","ts":…}`
- **Permission request** (hook→island, connection kept open):
  `{"type":"permission_request","request_id":"…","session_id":"…","project":"…","tool":"Bash","summary":"rm -rf …","cwd":"…","ts":…}`
- **Permission decision** (island→hook, on the same connection):
  `{"type":"permission_decision","request_id":"…","decision":"allow|deny","reason":"…"}`
  Decision `allow`→PreToolUse `permissionDecision:allow`; `deny`→`deny`; anything
  else / no reply → normal prompt.

## Manual control / testing (no UI needed)
`AgentService` exposes an IPC target:
```
qs -c openagentisland ipc call agent status        # {"sessions":N,"pending":M}
qs -c openagentisland ipc call agent allowOldest   # allow the oldest pending request
qs -c openagentisland ipc call agent denyOldest    # deny it
```

## Enabling the hooks in Claude Code (reversible, do when ready)
Not enabled automatically — it edits your live `~/.claude/settings.json`. When you
want it on, merge `hooks.settings.json` into `~/.claude/settings.json` (it only
adds a `hooks` block). To turn it off, remove that block. The bridge degrades
safely whether or not the island is running.
