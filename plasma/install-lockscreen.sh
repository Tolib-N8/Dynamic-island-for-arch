#!/usr/bin/env bash
# OpenAgentIsland — install the island-style kscreenlocker theme (Plasma 6).
#
# How it works: kscreenlocker's greeter loads its UI from the Plasma/Shell
# package (org.kde.plasma.desktop, key "lockscreenmainscript"). A user-local
# copy of the package under ~/.local/share/plasma/shells/ takes precedence, so
# we copy the WHOLE system package there (KPackage canonicalizes paths and
# rejects symlinks leading outside the package root — symlinks do NOT work,
# and a partial copy breaks package resolution entirely) and overlay our
# restyled contents/lockscreen/ on top.
#
# Trade-off: the user copy freezes the shell package until you re-run this
# script (do so after Plasma upgrades) or uninstall.
#
#   ./install-lockscreen.sh            install / refresh
#   ./install-lockscreen.sh uninstall  restore the stock lock screen
#   /usr/lib/kscreenlocker_greet --testing   preview without locking
set -euo pipefail

SYS=/usr/share/plasma/shells/org.kde.plasma.desktop
USR="$HOME/.local/share/plasma/shells/org.kde.plasma.desktop"
THEME="$(cd "$(dirname "$0")" && pwd)/lockscreen"

if [[ "${1:-}" == "uninstall" ]]; then
    rm -rf "$USR"
    echo "Removed $USR — stock lock screen restored."
    exit 0
fi

[[ -d "$SYS" ]] || { echo "System shell package not found: $SYS" >&2; exit 1; }
[[ -f "$THEME/LockScreenUi.qml" ]] || { echo "Theme not found: $THEME" >&2; exit 1; }

rm -rf "$USR"
mkdir -p "$USR"
cp -r "$SYS/." "$USR/"
cp "$THEME"/* "$USR/contents/lockscreen/"
echo "Installed island lock screen → $USR"
echo "Preview: /usr/lib/kscreenlocker_greet --testing"
