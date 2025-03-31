#!/bin/bash
# system_health_check.sh
# Consolidated system health check script that performs all basic system monitoring checks
# This script is called by the enhanced_monitoring_wrapper from deploy_monitoring.yml

# Initialize variables to track overall status
OVERALL_STATUS="success"
SUMMARY=""
FAILED_CHECKS=0
TOTAL_CHECKS=0

# Function to run a check and collect results
run_check() {
    local check_name="$1"
    local check_command="$2"
    local result
    local exit_code
    
    echo "Running check: $check_name"
    result=$(eval "$check_command" 2>&1)
    exit_code=$?
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ $exit_code -eq 0 ]; then
        echo "✅ $check_name: $result"
        SUMMARY="${SUMMARY}\n✅ $check_name: $result"
    else
        echo "❌ $check_name: $result"
        SUMMARY="${SUMMARY}\n❌ $check_name: $result"
        OVERALL_STATUS="failure"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Disk space check (integrated from testvolumequota script)
check_disk_space() {
    local dir="${1:-/}"
    local threshold="${2:-90}"
    
    # Get current usage percentage without the % sign
    local usage=$(df "$dir" | grep -v Filesystem | awk '{print $5}' | sed 's/%//g')
    
    if [ "$usage" -gt "$threshold" ]; then
        echo "Disk usage for $dir is at ${usage}% (threshold: ${threshold}%)"
        echo ""
        echo "Disk usage details:"
        df -h
        return 1
    else
        echo "Disk usage for $dir is at ${usage}% (below threshold: ${threshold}%)"
        return 0
    fi
}

# Memory usage check
check_memory() {
    local threshold="${1:-90}"
    
    local mem_info=$(free | grep Mem)
    local total=$(echo "$mem_info" | awk '{print $2}')
    local used=$(echo "$mem_info" | awk '{print $3}')
    local usage=$((used * 100 / total))
    
    if [ "$usage" -gt "$threshold" ]; then
        echo "Memory usage is at ${usage}% (threshold: ${threshold}%)"
        return 1
    else
        echo "Memory usage is at ${usage}% (below threshold: ${threshold}%)"
        return 0
    fi
}

# System load check
check_system_load() {
    local threshold="${1:-2}"
    
    local load=$(cat /proc/loadavg | awk '{print $1}')
    local load_int=$(echo "$load * 100" | bc | cut -d. -f1)
    local threshold_int=$(echo "$threshold * 100" | bc | cut -d. -f1)
    
    if [ "$load_int" -gt "$threshold_int" ]; then
        echo "System load is $load (threshold: $threshold)"
        return 1
    else
        echo "System load is $load (below threshold: $threshold)"
        return 0
    fi
}

# Network connectivity check
check_network() {
    if ping -c 3 -W 5 1.1.1.1 > /dev/null; then
        echo "Network connectivity check passed"
        return 0
    else
        echo "Network connectivity check failed"
        return 1
    fi
}

# Run all checks
echo "Starting system health checks at $(date)"

# Run all checks without passing arguments to run_check
run_check "disk_space_root" "check_disk_space / 90"
run_check "disk_space_home" "check_disk_space /home 90"
run_check "memory_usage" "check_memory 90"
run_check "system_load" "check_system_load 2"
run_check "network_connectivity" "check_network"

# Create a summary message
SUMMARY_HEADER="System Health Check Summary: $TOTAL_CHECKS checks performed, $FAILED_CHECKS failed"
FULL_SUMMARY="${SUMMARY_HEADER}${SUMMARY}"

echo "$SUMMARY_HEADER"
echo "Completed system health checks at $(date)"
echo "$FULL_SUMMARY"

# Exit with failure if any check failed
if [ "$OVERALL_STATUS" = "failure" ]; then
  exit 1
fi
