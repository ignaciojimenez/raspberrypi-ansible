#!/bin/bash
# 
# Script to check Raspotify service status and restart if needed

set -e          # stop on errors
set -u          # stop on unset variables
set -o pipefail # stop on pipe failures

if systemctl is-active --quiet raspotify; then
  echo "✅ Raspotify service is running"
  exit 0
else
  echo "❌ Raspotify service is not running - attempting restart"
  sudo systemctl restart raspotify
  sleep 5
  if systemctl is-active --quiet raspotify; then
    echo "✅ Raspotify service was successfully restarted"
    exit 0
  else
    echo "❌ Failed to restart Raspotify service"
    exit 1
  fi
fi
