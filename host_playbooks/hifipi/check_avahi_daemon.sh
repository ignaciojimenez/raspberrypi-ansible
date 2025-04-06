#!/bin/bash
# 
# Script to check Avahi daemon status and restart if needed

set -e          # stop on errors
set -u          # stop on unset variables
set -o pipefail # stop on pipe failures

if systemctl is-active --quiet avahi-daemon; then
  echo "✅ Avahi daemon is running"
  exit 0
else
  echo "❌ Avahi daemon is not running - attempting restart"
  sudo systemctl restart avahi-daemon
  sleep 5
  if systemctl is-active --quiet avahi-daemon; then
    echo "✅ Avahi daemon was successfully restarted"
    exit 0
  else
    echo "❌ Failed to restart Avahi daemon"
    exit 1
  fi
fi
