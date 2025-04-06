#!/bin/bash
# 
# Script to check audio output and volume settings

set -e          # stop on errors
set -u          # stop on unset variables
set -o pipefail # stop on pipe failures

# Check if ALSA is working properly
if aplay -l | grep -q 'card'; then
  # Check if volume is set correctly
  VOLUME=$(amixer sget 'PCM',0 | grep 'Mono:' | awk -F'[][]' '{ print $2 }' | tr -d '%')
  if [ "$VOLUME" -lt "90" ]; then
    echo "❌ Audio volume is too low ($VOLUME%) - setting to 100%"
    amixer sset 'PCM',0 100%
    alsactl store
    echo "✅ Audio volume has been reset to 100%"
    exit 0
  else
    echo "✅ Audio system is configured correctly (volume: $VOLUME%)"
    exit 0
  fi
else
  echo "❌ No audio devices found"
  exit 1
fi
