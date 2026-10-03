#!/usr/bin/env bash
# Installs a launchd agent that runs `deploy-to-device.sh` hourly (and at login).
# It retries until the phone is reachable. Logs: ~/Library/Logs/loopr-deploy.log.
set -euo pipefail

label="dev.willsawyerrrr.loopr-deploy"
plist="$HOME/Library/LaunchAgents/$label.plist"
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-to-device.sh"
log="$HOME/Library/Logs/loopr-deploy.log"

cat > "$plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$script</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
P

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed $label"
