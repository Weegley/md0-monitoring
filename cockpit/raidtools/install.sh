#!/bin/sh
set -eu
TARGET="/usr/local/share/cockpit/raidtools"
mkdir -p "$TARGET"
cp manifest.json index.html app.js app.css README.md "$TARGET"/
echo "Installed to $TARGET"
echo "Reload the Cockpit page in your browser."
