#!/bin/bash

# Set up the SoundFridge Host as a per-user macOS launchd service,
# analogous to a systemctl --user service on Linux.
#
# Run from the repository root:
#   packages/host/install-user-service.sh
#
# The Host release binary should be built first with:
#   swift build --package-path packages/host --configuration release
#

set -e

LABEL="com.soundbridge.host"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST_BINARY="$REPO_ROOT/packages/host/.build/release/SoundBridgeHost"

AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$LABEL.plist"

if [ ! -x "$HOST_BINARY" ]; then
  echo "SoundFridge Host release binary not found:"
  echo "  $HOST_BINARY"
  echo
  echo "Build it first with:"
  echo "  swift build --package-path packages/host --configuration release"
  exit 1
fi

mkdir -p "$AGENT_DIR"

cat >"$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$HOST_BINARY</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

plutil -lint "$AGENT_PLIST"

echo
echo "Installed LaunchAgent:"
echo "  $AGENT_PLIST"
echo
echo "Host binary:"
echo "  $HOST_BINARY"
