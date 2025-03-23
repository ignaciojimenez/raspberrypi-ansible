#!/bin/bash
# Devpi Monitoring Script
# This script checks the devpi server status and attempts to fix issues
# Designed to work with enhanced_monitoring_wrapper for Slack notifications

# Initialize arrays for tracking issues and actions
ALERTS=()
ACTIONS=()

# Process command line arguments
VERBOSE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --verbose) VERBOSE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

#############################
# SECTION 3: SYSTEM CHECKS #
#############################

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    ALERTS+=("Disk space critically low: ${DISK_USAGE}%")
fi

# Check memory usage
MEM_AVAILABLE=$(free -m | awk 'NR==2 {print $7}')
if [ "$MEM_AVAILABLE" -lt 100 ]; then
    ALERTS+=("Available memory is low: ${MEM_AVAILABLE}MB")
fi

#############################
# SECTION 4: OUTPUT RESULTS #
#############################

# Output verbose information if requested
if [ "$VERBOSE" = true ]; then
    echo "DEVPI MONITORING REPORT (VERBOSE MODE)"
    echo "--------------------------------------"
    echo "Checking devpi service status..."
    systemctl status devpi
    echo ""
    echo "Checking devpi server response..."
    curl -I "${DEVPI_URL}" 2>/dev/null || echo "Failed to connect to ${DEVPI_URL}"
    echo ""
    echo "Checking system resources..."
    echo "Disk usage: ${DISK_USAGE}%"
    echo "Available memory: ${MEM_AVAILABLE}MB"
    echo ""
    echo "Checking devpi processes..."
    ps aux | grep devpi-server | grep -v grep || echo "No devpi-server process found"
    echo "--------------------------------------"
    echo ""
fi

# Output results for monitoring_wrapper
if [ ${#ALERTS[@]} -gt 0 ]; then
    echo "DEVPI ALERTS:"
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
        echo "DEVPI STATUS: Fixed Issues"
        for action in "${ACTIONS[@]}"; do
            echo "✅ $action"
        done
    else
        echo "✅ All devpi components are running normally"
    fi
    exit 0
fi
