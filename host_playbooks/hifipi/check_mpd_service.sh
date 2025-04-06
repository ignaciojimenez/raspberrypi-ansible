#!/bin/bash
# 
# Script to check MPD service status and restart if needed

set -e          # stop on errors
set -u          # stop on unset variables
set -o pipefail # stop on pipe failures

if systemctl is-active --quiet mpd; then
  echo "✅ MPD service is running"
  exit 0
else
  echo "❌ MPD service is not running - attempting restart"
  sudo systemctl restart mpd
  sleep 5
  if systemctl is-active --quiet mpd; then
    echo "✅ MPD service was successfully restarted"
    exit 0
  else
    echo "❌ Failed to restart MPD service"
    exit 1
  fi
fi
