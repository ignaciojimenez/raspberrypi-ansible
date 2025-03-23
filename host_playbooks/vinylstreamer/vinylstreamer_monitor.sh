#!/bin/bash
# Vinylstreamer Comprehensive Monitoring Script
# This script checks all components of the vinylstreamer system
# Designed to work with monitoring_wrapper for Slack notifications

# Initialize arrays for tracking issues and actions
ALERTS=()
ACTIONS=()

#############################
# SECTION 1: SERVICE CHECKS #
#############################

# Check all required services
SERVICES=("icecast2" "phono_liquidsoap" "detect_audio")
for service in "${SERVICES[@]}"; do
    if ! sudo systemctl is-active --quiet "$service"; then
        ALERTS+=("$service service is not running")
        ACTIONS+=("Attempting to restart $service service")
        sudo systemctl restart "$service"
        sleep 3
        
        if ! sudo systemctl is-active --quiet "$service"; then
            ALERTS+=("Failed to restart $service service")
        else
            ACTIONS+=("$service service restarted successfully")
        fi
    fi
done

##############################
# SECTION 2: HARDWARE CHECKS #
##############################

# Check for audio input device
if ! arecord -l | grep -q 'card'; then
    ALERTS+=("No audio capture device found")
fi

# Check CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
    ALERTS+=("High CPU usage detected: $CPU_USAGE%")
fi

#############################
# SECTION 3: STREAM CHECKS #
#############################

# Check if the "source" key exists in Icecast status JSON
ICECAST_STATUS_URL="http://localhost:8000/status-json.xsl"
STREAM_NAME="phono.ogg"

if command -v jq >/dev/null 2>&1; then
    # Check if source key exists in JSON response
    SOURCE_EXISTS=$(curl -s "$ICECAST_STATUS_URL" | jq -r 'if .icestats.source != null then "true" else "false" end')
    
    if [ "$SOURCE_EXISTS" != "true" ]; then
        ALERTS+=("No source key found in Icecast status")
        
        # Self-healing: If Icecast is running but source is missing, restart Liquidsoap
        if sudo systemctl is-active --quiet icecast2; then
            ACTIONS+=("Icecast is running but source key is missing - restarting Liquidsoap")
            sudo systemctl restart phono_liquidsoap.service
            sleep 10
            
            # Check if that fixed the issue
            SOURCE_EXISTS=$(curl -s "$ICECAST_STATUS_URL" | jq -r 'if .icestats.source != null then "true" else "false" end')
            if [ "$SOURCE_EXISTS" = "true" ]; then
                ACTIONS+=("Source key now exists after restarting Liquidsoap")
            else
                ALERTS+=("Source key still missing after restarting Liquidsoap")
            fi
        fi
    fi
else
    # Fallback to grep if jq is not available
    if ! curl -s "$ICECAST_STATUS_URL" | grep -q '"source"'; then
        ALERTS+=("No source key found in Icecast status (grep check)")
        
        # Self-healing: If Icecast is running but source is missing, restart Liquidsoap
        if sudo systemctl is-active --quiet icecast2; then
            ACTIONS+=("Icecast is running but source key is missing - restarting Liquidsoap")
            sudo systemctl restart phono_liquidsoap.service
            sleep 10
            
            # Check if that fixed the issue
            if curl -s "$ICECAST_STATUS_URL" | grep -q '"source"'; then
                ACTIONS+=("Source key now exists after restarting Liquidsoap")
            else
                ALERTS+=("Source key still missing after restarting Liquidsoap")
            fi
        fi
    fi
fi

#############################
# SECTION 4: PROCESS CHECKS #
#############################

# Check detect_audio.py process
if ! pgrep -f "detect_audio.py" > /dev/null; then
    ALERTS+=("detect_audio.py process is not running")
    ACTIONS+=("Attempting to restart detect_audio service")
    
    sudo systemctl restart detect_audio
    sleep 5
    
    if pgrep -f "detect_audio.py" > /dev/null; then
        ACTIONS+=("Successfully restarted detect_audio.py process")
    else
        ALERTS+=("Failed to restart detect_audio.py process")
    fi
fi

#############################
# SECTION 5: OUTPUT RESULTS #
#############################

# Output results for monitoring_wrapper
if [ ${#ALERTS[@]} -gt 0 ]; then
    echo "VINYLSTREAMER ALERTS:"
    for alert in "${ALERTS[@]}"; do
        echo "❌ $alert"
    done
    
    if [ ${#ACTIONS[@]} -gt 0 ]; then
        echo ""
        echo "ACTIONS TAKEN:"
        for action in "${ACTIONS[@]}"; do
            echo "✅ $action"
        done
    fi
    
    exit 1
else
    if [ ${#ACTIONS[@]} -gt 0 ]; then
        echo "VINYLSTREAMER STATUS: Fixed Issues"
        for action in "${ACTIONS[@]}"; do
            echo "✅ $action"
        done
    else
        echo "✅ All vinylstreamer components are running normally"
    fi
    exit 0
fi
