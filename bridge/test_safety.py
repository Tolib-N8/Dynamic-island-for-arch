#!/usr/bin/env python3
"""
Safety test harness for the OpenAgentIsland hook bridge.

Proves the hook NEVER hangs or breaks Claude Code across every failure mode:
listener down, listener present (allow/deny), and listener frozen. This is the
MANDATED safety check — a broken island must never make real Claude Code
unusable. Run: python3 bridge/test_safety.py
"""
import json
import os
import signal
import subprocess
import sys
import time

DIR = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(DIR, "oai_hook.py")
MOCK = os.path.join(DIR, "mock_listener.py")
SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "openagentisland.sock")
ENV = {**os.environ, "OAI_PERMISSION_TIMEOUT": "3"}  # short for testing

PRETOOL = json.dumps({"hook_event_name": "PreToolUse", "session_id": "s1",
                      "cwd": "/home/x/proj", "tool_name": "Bash",
                      "tool_input": {"command": "rm -rf /tmp/foo"}})
STATUS = json.dumps({"hook_event_name": "PostToolUse", "session_id": "s1",
                     "cwd": "/home/x/proj", "tool_name": "Bash",
                     "tool_input": {"command": "ls"}})

results = []


def check(name, ok, extra=""):
    results.append(bool(ok))
    tag = "PASS" if ok else "FAIL"
    suffix = f" — {extra}" if (extra and not ok) else ""
    print(f"  {tag}: {name}{suffix}")


def run_hook(mode, payload, timeout=15):
    t0 = time.time()
    p = subprocess.run([sys.executable, HOOK, mode], input=payload.encode(),
                       capture_output=True, timeout=timeout, env=ENV)
    return p.returncode, p.stdout.decode().strip(), time.time() - t0


def start_mock(mode):
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    p = subprocess.Popen([sys.executable, MOCK, mode],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    time.sleep(0.5)
    return p


def stop_mock(p):
    p.send_signal(signal.SIGTERM)
    try:
        out, _ = p.communicate(timeout=2)
    except Exception:
        p.kill()
        out = b""
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    return out.decode() if out else ""


print("T1 — listener DOWN, status event:")
if os.path.exists(SOCK):
    os.unlink(SOCK)
rc, out, dur = run_hook("status", STATUS)
check("exit 0", rc == 0)
check("no output", out == "")
check("fast (<1s)", dur < 1, f"{dur:.2f}s")

print("T2 — listener DOWN, permission (must fall back to normal prompt):")
rc, out, dur = run_hook("permission", PRETOOL)
check("exit 0", rc == 0)
check("no decision output", out == "", out)
check("fast (<1s)", dur < 1, f"{dur:.2f}s")

print("T3 — listener ALLOW:")
m = start_mock("allow")
rc, out, dur = run_hook("permission", PRETOOL)
stop_mock(m)
check("emits allow", '"permissionDecision": "allow"' in out, out)
check("exit 0", rc == 0)

print("T4 — listener DENY:")
m = start_mock("deny")
rc, out, dur = run_hook("permission", PRETOOL)
stop_mock(m)
check("emits deny", '"permissionDecision": "deny"' in out, out)

print("T5 — listener FROZEN (must time out → fall back, bounded time):")
m = start_mock("hang")
rc, out, dur = run_hook("permission", PRETOOL, timeout=15)
stop_mock(m)
check("exit 0 after freeze", rc == 0)
check("no decision (fallback)", out == "", out)
check("bounded near timeout (<5s)", dur < 5, f"{dur:.2f}s")

print("T6 — listener UP, status event delivered:")
m = start_mock("allow")
run_hook("status", STATUS)
time.sleep(0.3)
log = stop_mock(m)
check("received by listener", '"event": "PostToolUse"' in log, log[-200:])

passed = sum(results)
print(f"\nRESULT: {passed}/{len(results)} checks passed")
sys.exit(0 if passed == len(results) else 1)
