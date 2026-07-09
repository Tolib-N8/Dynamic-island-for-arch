#!/usr/bin/env python3
"""
OpenAgentIsland — AI usage/limits poller (CodexBar-style, Linux edition).

Prints one JSON object with the remaining-quota picture for AI platforms:

  {"providers": [
    {"id":"codex","label":"Codex","usedPct":46.0,"remainingPct":54.0,
     "resetsAt":1786125907,"windowMinutes":43200,"plan":"go","estimate":false},
    {"id":"claude","label":"Claude","usedPct":53.6,"remainingPct":46.4,
     "resetsAt":1783717200,"windowMinutes":300,"plan":"5h block",
     "estimate":true,"detail":"44.4M / 82.8M tok"}
  ]}

Sources (same idea as CodexBar, which is macOS-only — we read the data instead):
- Codex CLI writes exact subscription rate-limit snapshots into its session
  files (~/.codex/sessions/**/rollout-*.jsonl, "rate_limits" events with
  primary.used_percent / resets_at / window_minutes / plan_type).
- Claude Code has no local exact quota; we estimate the current 5h block via
  ccusage (tokens vs the historical max block), cached for 5 minutes because
  npx is slow. Marked "estimate": true.

Never raises: a failing provider is simply omitted.
"""
import glob
import json
import os
import subprocess
import sys
import time

CACHE = "/tmp/oai-ai-usage-cache.json"
CCUSAGE_TTL = 300  # s


def newest_session_files(root, n=4):
    files = glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[:n]


def tail_bytes(path, size=262144):
    with open(path, "rb") as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - size))
        return f.read().decode("utf-8", "replace")


def find_rate_limits(obj):
    if isinstance(obj, dict):
        if "rate_limits" in obj and isinstance(obj["rate_limits"], dict):
            return obj["rate_limits"]
        for v in obj.values():
            r = find_rate_limits(v)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_rate_limits(v)
            if r is not None:
                return r
    return None


def codex_provider():
    root = os.path.expanduser("~/.codex/sessions")
    if not os.path.isdir(root):
        return None
    for path in newest_session_files(root):
        best = None
        for line in tail_bytes(path).splitlines():
            if "rate_limits" not in line:
                continue
            try:
                rl = find_rate_limits(json.loads(line))
            except Exception:
                continue
            if rl and rl.get("primary"):
                best = rl  # keep the LAST snapshot in the file
        if best:
            p = best["primary"]
            used = float(p.get("used_percent", 0.0))
            return {
                "id": "codex",
                "label": "Codex",
                "usedPct": round(used, 1),
                "remainingPct": round(100.0 - used, 1),
                "resetsAt": p.get("resets_at"),
                "windowMinutes": p.get("window_minutes"),
                "plan": best.get("plan_type") or "",
                "estimate": False,
            }
    return None


def human_tokens(n):
    if n >= 1e9:
        return f"{n/1e9:.1f}B"
    if n >= 1e6:
        return f"{n/1e6:.1f}M"
    if n >= 1e3:
        return f"{n/1e3:.0f}K"
    return str(int(n))


def claude_provider():
    # cached ccusage call (npx is slow)
    now = time.time()
    try:
        c = json.load(open(CACHE))
        if now - c.get("ts", 0) < CCUSAGE_TTL:
            return c.get("provider")
    except Exception:
        pass

    provider = None
    try:
        out = subprocess.run(
            ["npx", "-y", "ccusage@latest", "blocks", "--json"],
            capture_output=True, text=True, timeout=120,
        ).stdout
        data = json.loads(out)
        blocks = [b for b in data.get("blocks", []) if not b.get("isGap")]
        # Personal 5h ceiling ≈ the largest block ever completed (ccusage's own
        # "--token-limit max" idea; the JSON output doesn't fill tokenLimitStatus,
        # so compute it ourselves).
        limit = max((float(b.get("totalTokens", 0)) for b in blocks
                     if not b.get("isActive")), default=0) or None
        for b in blocks:
            if not b.get("isActive"):
                continue
            total = float(b.get("totalTokens", 0))
            used = min(total / limit * 100.0, 100.0) if limit else None
            resets = None
            if b.get("endTime"):
                try:
                    from datetime import datetime
                    resets = int(datetime.fromisoformat(
                        b["endTime"].replace("Z", "+00:00")).timestamp())
                except Exception:
                    pass
            provider = {
                "id": "claude",
                "label": "Claude",
                "usedPct": round(used, 1) if used is not None else None,
                "remainingPct": round(100.0 - used, 1) if used is not None else None,
                "resetsAt": resets,
                "windowMinutes": 300,
                "plan": "5h block",
                "estimate": True,
                "detail": f"{human_tokens(total)}" + (f" / {human_tokens(limit)} tok" if limit else " tok"),
            }
            break
    except Exception:
        provider = None

    try:
        json.dump({"ts": now, "provider": provider}, open(CACHE, "w"))
    except Exception:
        pass
    return provider


def main():
    providers = []
    for p in (claude_provider(), codex_provider()):
        if p:
            providers.append(p)
    print(json.dumps({"providers": providers, "ts": int(time.time())}))


if __name__ == "__main__":
    main()
