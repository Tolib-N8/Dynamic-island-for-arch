# PROGRESS.md — OpenAgentIsland work log

Chronological log. Newest first within each section. Architecture/design rationale
lives in `NOTES.md`.

---

## Current phase & status

**Phase 0 — Orient: DONE (pending user confirmation of the nested dev window).**

- Reference (`modules/notch.py`, `utils/animator.py`) read and analyzed.
- `NOTES.md` created: reference findings, Fabric→Quickshell mapping table,
  three-island architecture, full notch state machine + precedence, agent bridge
  design (socket, hooks, JSON schema, blocking protocol, safety/timeout).
- `PROGRESS.md` created (this file).
- Dev environment verified present (see "Done").
- **Nothing renders yet** — the islands are not wired into the panel family.

**What works:** repo, runtime symlink, nested dev config all in place. end-4 base
shell loads (`openagentisland` config).
**What doesn't:** no islands shown — `Bar` still active, `Island {}` PanelLoader still
commented out. The three island components don't exist yet (only a skeleton sketch).

---

## Done (newest first)

- **2026-06-03 — Phase 0 orientation.**
  - Read `~/Projects/island-reference/hyprfabricated/modules/notch.py` (995 lines) and
    `utils/animator.py`. Key finding: their notch "morph" is a GTK `Stack` with
    `set_interpolate_size(True)` swapping fixed-size children, NOT a width/height tween;
    the functional left/right clusters live in a separate full-width bar (we split those
    into two floating islands); single-window, no multi-monitor. animator.py is a
    hand-rolled cubic-bezier tick tween → replaced by native Qt `Behavior`/`easing`.
  - Wrote `NOTES.md` and `PROGRESS.md`.
  - **Surveyed current repo state:**
    - `panelFamilies/IllogicalImpulseFamily.qml`: full-width `Bar` PanelLoader ACTIVE;
      `// PanelLoader { component: Island {} }` commented out; `qs.modules.ii.island`
      already imported.
    - `modules/ii/island/` already contains a **prior-session sketch**:
      `Island.qml` (static 220×32 "island" pill, single `PanelWindow` in `Variants`,
      anchored top-center) and `IslandContent.qml` (volume-only state machine where
      `idle` is *invisible* and the trigger is `GlobalStates.osdVolumeOpen`). Both
      diverge from the target design (idle should be a minimal clock; trigger off the
      `Audio` value, not the flickering flag). Treat as a sketch to rewrite in Phase 3.
  - **Dev env confirmed present:**
    - Runtime symlink OK: `~/.config/quickshell/openagentisland` →
      `~/Projects/openagentisland/quickshell`.
    - Nested Hyprland config OK: `~/.config/hypr-nested/hyprland.conf`
      (monitor `WL-1 2560x1440@60`, `exec-once = qs -c openagentisland`,
      animations/blur disabled).
    - The live `ii` config is untouched (hard rule).

---

## Next

1. **User action:** launch the nested dev window and confirm `openagentisland` renders:
   `WLR_BACKENDS=wayland WLR_NO_HARDWARE_CURSORS=1 HYPRLAND_INSTANCE_SIGNATURE= Hyprland --config ~/.config/hypr-nested/hyprland.conf`
2. **Phase 1 — Floating skeleton:** disable the `Bar` PanelLoader; build
   `IslandLeft` / `IslandNotch` / `IslandRight` as three transparent rounded
   `PanelWindow`s, each in `Variants` over `Quickshell.screens`, anchored
   top-left/center/right with margins; register their PanelLoaders. Verify: three
   floating pills, wallpaper through the gaps, no bar — on every monitor.

---

## Blockers / open questions

- (Phase 6) Confirm `Quickshell.Io` 0.2.1 supports a listening socket +
  bidirectional/blocking writes from QML; if awkward, propose an external listener
  daemon to the user before building.
- Memory file `project_openagentland.md` describes this as a "fork of dynisland" —
  that is **stale/incorrect**; the actual project is Quickshell/QML on end-4 per
  `CLAUDE.md`. Trusting `CLAUDE.md` + the repo.

---

## Gotchas hit

- User shell is **fish** — no `<<EOF` heredocs; write files with tools or
  `printf`/`cat` inside `bash -c '...'`. (A chained `ls A B && find …` failed because
  fish/`ls` returned exit 2 when one path was missing and short-circuited the `&&`.)
- A prior session already scaffolded `modules/ii/island/` — check existing files before
  creating, to avoid clobbering or duplicating.
