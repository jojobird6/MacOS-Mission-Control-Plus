#!/bin/bash
set -euo pipefail
BUNDLE_ID="com.joseph.mcclose"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
rm -rf "/Applications/MCClose.app"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
echo "MCClose uninstalled."
