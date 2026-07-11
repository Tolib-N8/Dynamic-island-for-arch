#!/usr/bin/env bash
# Install the OpenAgentIsland global shortcuts (Meta+V → clipboard page).
# Idempotent; re-run after changing the kwin script.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# 1. systemd user unit the kwin script triggers (scripts can't spawn processes)
mkdir -p ~/.config/systemd/user
cp "$here/oai-clipboard.service" ~/.config/systemd/user/
systemctl --user daemon-reload

# 2. kwin script with the actual shortcut binding
mkdir -p ~/.local/share/kwin/scripts
cp -r "$here/kwin-script/oai-shortcuts" ~/.local/share/kwin/scripts/
kwriteconfig6 --notify --file kwinrc --group Plugins --key oai-shortcutsEnabled true
busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s "oai-shortcuts" >/dev/null 2>&1 || true
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure

echo "Installed. Check: busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting isScriptLoaded s oai-shortcuts"
