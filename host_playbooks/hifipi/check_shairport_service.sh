#!/bin/bash
# 
# Script to check Shairport-sync service status and restart if needed

set -e          # stop on errors
set -u          # stop on unset variables
set -o pipefail # stop on pipe failures

if systemctl is-active --quiet shairport-sync; then
  echo "✅ Shairport-sync service is running"
  exit 0
else
  echo "❌ Shairport-sync service is not running - attempting restart"
  sudo systemctl restart shairport-sync
  sleep 5
  if systemctl is-active --quiet shairport-sync; then
    echo "✅ Shairport-sync service was successfully restarted"
    exit 0
  else
    echo "❌ Failed to restart Shairport-sync service"
    exit 1
  fi
fi
