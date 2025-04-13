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

# Auto-upgrades check
check_auto_upgrades() {
    local issues_found=0
    local actions_taken=0
    local output=""
    
    # Check if unattended-upgrades is installed
    if ! sudo dpkg -l | grep -q unattended-upgrades; then
        output="${output}\nunattended-upgrades package is not installed"
        issues_found=$((issues_found + 1))
    fi

    # Check if the service is enabled
    if ! sudo systemctl is-enabled unattended-upgrades.service &>/dev/null; then
        output="${output}\nunattended-upgrades service is not enabled"
        
        # Self-healing: Enable the service
        sudo systemctl enable unattended-upgrades.service &>/dev/null
        if [ $? -eq 0 ]; then
            output="${output}\nACTIONS TAKEN: Enabled unattended-upgrades service"
            actions_taken=$((actions_taken + 1))
        fi
        
        issues_found=$((issues_found + 1))
    fi

    # Check if the service is active
    if ! sudo systemctl is-active unattended-upgrades.service &>/dev/null; then
        output="${output}\nunattended-upgrades service is not running"
        
        # Self-healing: Start the service
        sudo systemctl start unattended-upgrades.service &>/dev/null
        if [ $? -eq 0 ]; then
            output="${output}\nACTIONS TAKEN: Started unattended-upgrades service"
            actions_taken=$((actions_taken + 1))
        fi
        
        issues_found=$((issues_found + 1))
    fi

    # Check for recent unattended-upgrade activity
    local upgrade_activity_found=false
    local upgrade_evidence=""
    
    # Check for reboot-required file which indicates successful upgrades
    if sudo test -f /var/run/reboot-required; then
        upgrade_activity_found=true
        upgrade_evidence="Found /var/run/reboot-required file, indicating successful security upgrades"
    fi
    
    # Check log file for various upgrade patterns
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        # Look for various patterns that indicate upgrade activity
        local recent_logs=$(sudo grep -E "Unattended upgrade|unattended-upgrade|packages upgraded|packages to upgrade|packages to install|reboot-required" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -v "DEBUG" | tail -n 20)
        
        # Print the recent logs for debugging
        output="${output}\n\nRecent upgrade-related log entries (last 20):\n$recent_logs"
        
        # If we have any log entries, that's evidence of activity
        if [ -n "$recent_logs" ]; then
            upgrade_activity_found=true
            if [ -z "$upgrade_evidence" ]; then
                upgrade_evidence="Found upgrade-related entries in logs"
            fi
        fi
        
        # Check for scheduled reboots which indicate successful upgrades
        if echo "$recent_logs" | grep -q "reboot"; then
            upgrade_activity_found=true
            upgrade_evidence="${upgrade_evidence}\nFound evidence of scheduled reboot after upgrades"
        fi
    else
        output="${output}\n\nUnattended-upgrades log file not found"
    fi
    
    # Also check apt history logs as an alternative source
    if [ -d /var/log/apt ]; then
        local apt_history=$(sudo grep -l "unattended-upgrades" /var/log/apt/history.log* 2>/dev/null | head -n 1)
        if [ -n "$apt_history" ]; then
            local apt_entries=$(sudo zgrep -a "Commandline: /usr/bin/unattended-upgrade" "$apt_history" 2>/dev/null | tail -n 5)
            if [ -n "$apt_entries" ]; then
                upgrade_activity_found=true
                upgrade_evidence="${upgrade_evidence}\nFound unattended-upgrade entries in apt history logs"
                output="${output}\n\nApt history log entries:\n$apt_entries"
            fi
        fi
    fi
    
    # Final determination based on all evidence
    if [ "$upgrade_activity_found" = false ]; then
        output="${output}\n\nNo evidence of recent unattended-upgrade activity found"
        issues_found=$((issues_found + 1))
    else
        output="${output}\n\nEvidence of unattended-upgrade activity found:\n$upgrade_evidence"
    fi

    # Check for failed upgrade attempts
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        local failed_upgrades=$(sudo grep -i "error\|fail" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -v "DEBUG\|warning" | tail -n 10)
        
        # Print the failed upgrades for debugging
        if [ -n "$failed_upgrades" ]; then
            output="${output}\n\nPotential upgrade errors found in logs:\n$failed_upgrades"
            issues_found=$((issues_found + 1))
        else
            # Check for warnings separately
            local warnings=$(sudo grep -i "warning" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -v "DEBUG" | tail -n 5)
            if [ -n "$warnings" ]; then
                output="${output}\n\nWarnings in logs (not counted as errors):\n$warnings"
            else
                output="${output}\n\nNo upgrade issues found in logs"
            fi
        fi
    fi

    # Check for pending updates
    local pending_updates=$(sudo apt-get --simulate upgrade 2>/dev/null | grep -c "^Inst")
    if [ "$pending_updates" -gt 10 ]; then
        output="${output}\n\nLarge number of pending updates ($pending_updates) - unattended upgrades may not be working properly"
        issues_found=$((issues_found + 1))
    else
        output="${output}\n\nNormal number of pending updates: $pending_updates"
    fi
    
    # Show what updates are pending
    local pending_update_list=$(sudo apt-get --simulate upgrade 2>/dev/null | grep "^Inst" | head -n 5)
    if [ -n "$pending_update_list" ]; then
        output="${output}\n\nSample of pending updates:\n$pending_update_list"
    fi

    # Check configuration files
    if [ ! -f /etc/apt/apt.conf.d/20auto-upgrades ] || [ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        output="${output}\nMissing one or more configuration files"
        issues_found=$((issues_found + 1))
    else
        # Check for key settings in config files
        if ! sudo grep -q "APT::Periodic::Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades; then
            output="${output}\nUnattended upgrades not enabled in 20auto-upgrades"
            issues_found=$((issues_found + 1))
        fi
    fi

    # Summary
    if [ $issues_found -eq 0 ]; then
        echo "Auto-upgrades are properly configured and running"
        return 0
    else
        echo "Auto-upgrades check found $issues_found issues"
        echo "$output"
        
        if [ $actions_taken -gt 0 ]; then
            echo "Self-healing actions taken: $actions_taken"
        fi
        
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
run_check "auto_upgrades" "check_auto_upgrades"

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
