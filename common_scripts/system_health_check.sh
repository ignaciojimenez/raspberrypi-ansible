#!/bin/bash
# system_health_check.sh
# Consolidated system health check script that performs all basic system monitoring checks
# This script is called by the enhanced_monitoring_wrapper from deploy_monitoring.yml

# Initialize variables
failed_checks=0
total_checks=0
start_time=$(date)
output_summary=""
verbose_output=""

echo "Starting system health checks at $start_time"

# Function to run a check and report results
run_check() {
    local check_name=$1
    local check_function=$2
    
    echo "Running check: $check_name"
    
    # Use a temporary file to capture the exit status reliably
    local tmpfile=$(mktemp)
    
    # Run the check function and capture both output and exit status
    # The function will write its output to the temporary file
    eval "$check_function > $tmpfile"
    local status=$?
    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"
    
    # Increment the total number of checks
    total_checks=$((total_checks + 1))
    
    # If the check failed, increment the failed checks counter
    if [ $status -ne 0 ]; then
        failed_checks=$((failed_checks + 1))
        output_summary="$output_summary\n❌ $check_name: $result"
        verbose_output="$verbose_output\n\n--- $check_name DETAILS ---$result"
        # Display the result with proper newlines
        formatted_result=$(echo "$result" | sed 's/\\n/\n/g')
        echo -e "❌ $check_name: $formatted_result"
    else
        output_summary="$output_summary\n✅ $check_name: $result"
        # Display the result with proper newlines
        formatted_result=$(echo "$result" | sed 's/\\n/\n/g')
        echo -e "✅ $check_name: $formatted_result"
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
    local summary=""
    
    # Check if unattended-upgrades is installed
    if ! dpkg -l | grep -q "unattended-upgrades"; then
        summary="${summary}\n- Unattended-upgrades package is not installed"
        issues_found=$((issues_found + 1))
        
        # Self-healing: attempt to install the package
        sudo apt-get install -y unattended-upgrades >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            summary="${summary}\n- FIXED: Installed unattended-upgrades package"
            actions_taken=$((actions_taken + 1))
        fi
    fi
    
    # Check if the service is enabled and running
    if ! systemctl is-enabled unattended-upgrades.service >/dev/null 2>&1; then
        summary="${summary}\n- Unattended-upgrades service is not enabled"
        issues_found=$((issues_found + 1))
        
        # Self-healing: enable the service
        sudo systemctl enable unattended-upgrades.service >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            summary="${summary}\n- FIXED: Enabled unattended-upgrades service"
            actions_taken=$((actions_taken + 1))
        fi
    fi
    
    if ! systemctl is-active unattended-upgrades.service >/dev/null 2>&1; then
        summary="${summary}\n- Unattended-upgrades service is not running"
        issues_found=$((issues_found + 1))
        
        # Self-healing: start the service
        sudo systemctl start unattended-upgrades.service >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            summary="${summary}\n- FIXED: Started unattended-upgrades service"
            actions_taken=$((actions_taken + 1))
        fi
    fi
    
    # Check for evidence of recent unattended-upgrade activity
    local upgrade_activity_found=false
    local upgrade_evidence=""
    
    # Check for reboot-required file which indicates successful upgrades
    if sudo test -f /var/run/reboot-required; then
        upgrade_activity_found=true
        upgrade_evidence="reboot-required file found"
    fi
    
    # Check unattended-upgrades log for recent activity (last 7 days)
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        local recent_runs=$(sudo grep "Starting unattended upgrades script" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | tail -n 5)
        if [ -n "$recent_runs" ]; then
            # Check if any run was in the last 7 days
            local latest_run=$(echo "$recent_runs" | tail -n 1 | cut -d',' -f1)
            local run_date=$(echo "$latest_run" | cut -d' ' -f1)
            local current_date=$(date +"%Y-%m-%d")
            
            # Simple date comparison - if it's from today or recent days, consider it active
            if [ "$run_date" = "$current_date" ] || [ -n "$(echo "$recent_runs" | grep "$(date -d '1 day ago' +"%Y-%m-%d" 2>/dev/null || date -v-1d +"%Y-%m-%d" 2>/dev/null)")" ] || [ -n "$(echo "$recent_runs" | grep "$(date -d '2 days ago' +"%Y-%m-%d" 2>/dev/null || date -v-2d +"%Y-%m-%d" 2>/dev/null)")" ]; then
                upgrade_activity_found=true
                upgrade_evidence="recent unattended-upgrades runs"
                output="${output}\nLatest run: $latest_run"
                
                # Also check what the latest run accomplished
                local latest_log_entry=$(sudo grep -A 5 "$latest_run" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | tail -n 5)
                if echo "$latest_log_entry" | grep -q "No packages found that can be upgraded"; then
                    output="${output}\nStatus: System up to date (no packages to upgrade)"
                elif echo "$latest_log_entry" | grep -q "upgraded"; then
                    output="${output}\nStatus: Packages were upgraded"
                fi
            fi
        fi
    fi
    
    # Also check apt history for unattended-upgrade activity
    for apt_history in /var/log/apt/history.log /var/log/apt/history.log.1.gz; do
        if [ -f "$apt_history" ]; then
            local apt_entries=$(sudo zgrep -a "Commandline: /usr/bin/unattended-upgrade" "$apt_history" 2>/dev/null | tail -n 2)
            if [ -n "$apt_entries" ]; then
                upgrade_activity_found=true
                upgrade_evidence="${upgrade_evidence}, apt history entries"
                output="${output}\nApt history: $(echo "$apt_entries" | head -n 1 | tr '\n' ' ')..."
            fi
        fi
    done
    
    # Check for evidence of recent unattended-upgrade activity
    if [ "$upgrade_activity_found" = false ]; then
        summary="${summary}\n- No evidence of recent unattended-upgrade activity"
        issues_found=$((issues_found + 1))
    else
        output="${output}\nUpgrade evidence: $upgrade_evidence"
    fi

    # Check for failed upgrade attempts since the last scheduled run
    if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
        # Get current date and time
        local current_date=$(date +"%Y-%m-%d")
        local current_hour=$(date +"%H" | sed 's/^0//')
        
        # Determine the date we should check for errors based on the full upgrade cycle
        # - Upgrades run at 6:00-7:00 AM
        # - Reboots (if needed) happen at 4:00 AM the next day
        local check_date
        if [ "$current_hour" -lt 4 ]; then
            # Before reboot time (4:00 AM), check two days ago's upgrade cycle
            check_date=$(date -d "2 days ago" +"%Y-%m-%d" 2>/dev/null || date -v-2d +"%Y-%m-%d" 2>/dev/null)
        elif [ "$current_hour" -lt 7 ]; then
            # Between reboot (4:00 AM) and upgrade (7:00 AM), check yesterday's upgrade cycle
            check_date=$(date -d "1 day ago" +"%Y-%m-%d" 2>/dev/null || date -v-1d +"%Y-%m-%d" 2>/dev/null)
        else
            # After today's upgrade (post 7:00 AM), check today's upgrade cycle
            check_date="$current_date"
        fi
        
        # Find the last scheduled upgrade run time (around 6:00-7:00 AM on check_date)
        local last_scheduled_run=$(sudo grep "Writing dpkg log" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep "$check_date" | grep -E "0?6:|0?7:" | tail -n 1 | cut -d' ' -f1-2)
        
        # Also check for reboot evidence at 4:00 AM (which would be the day after check_date)
        local reboot_date
        if [ "$current_hour" -lt 4 ]; then
            # Before today's reboot time
            reboot_date=$(date -d "1 day ago" +"%Y-%m-%d" 2>/dev/null || date -v-1d +"%Y-%m-%d" 2>/dev/null)
        else
            # After today's reboot time
            reboot_date="$current_date"
        fi
        local reboot_evidence=$(sudo grep "Automatic-Reboot" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep "$reboot_date" | grep -E "0?4:" | tail -n 1)
        
        # If we can't find the scheduled run, look for any run on that day
        if [ -z "$last_scheduled_run" ]; then
            last_scheduled_run=$(sudo grep "Writing dpkg log" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep "$check_date" | tail -n 1 | cut -d' ' -f1-2)
        fi
        
        # Get errors since the last scheduled run
        local failed_upgrades
        if [ -n "$last_scheduled_run" ]; then
            # Get errors since the last scheduled run
            local timestamp_line=$(sudo grep -n "$last_scheduled_run" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | cut -d':' -f1)
            if [ -n "$timestamp_line" ]; then
                failed_upgrades=$(sudo tail -n +"$timestamp_line" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -i "error\|fail" | grep -v "DEBUG\|warning" | tail -n 3)
            fi
        else
            # Fallback: check last 24 hours if we can't find the scheduled run
            local yesterday=$(date -d "1 day ago" +"%Y-%m-%d" 2>/dev/null || date -v-1d +"%Y-%m-%d" 2>/dev/null)
            failed_upgrades=$(sudo grep -i "error\|fail" /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | grep -v "DEBUG\|warning" | grep -E "$current_date|$yesterday" | tail -n 3)
        fi
        
        # Process any failed upgrades
        if [ -n "$failed_upgrades" ]; then
            local error_sample=$(echo "$failed_upgrades" | head -n 1 | tr -d '\n')
            
            # Extract the date and hour from the error message
            local error_date=$(echo "$error_sample" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -n 1)
            local error_hour=$(echo "$error_sample" | grep -oE "[0-9]{2}:[0-9]{2}" | head -n 1 | cut -d':' -f1)
            
            # Get current date and hour
            local current_date=$(date +"%Y-%m-%d")
            local current_hour=$(date +"%H")
            
            # Simple time comparison - consider errors from today and within 3 hours as recent
            local is_recent=false
            
            if [ "$error_date" = "$current_date" ]; then
                # It's from today, check if it's within the last 3 hours
                local hour_diff=$((current_hour - error_hour))
                if [ $hour_diff -le 3 ]; then
                    is_recent=true
                fi
            fi
            
            # Add debug output
            output="${output}\nDEBUG: Error date: $error_date, Error hour: $error_hour, Current date: $current_date, Current hour: $current_hour"
            
            # Only consider recent errors as active issues
            if [ "$is_recent" = true ]; then
                if [ -n "$last_scheduled_run" ]; then
                    # If we have reboot evidence after the errors, note that the cycle completed
                    if [ -n "$reboot_evidence" ] && [ "$(date -d "$last_scheduled_run" +%s 2>/dev/null || date -jf "%Y-%m-%d %H:%M:%S" "$last_scheduled_run" +%s 2>/dev/null)" -lt "$(date -d "$reboot_date 04:00:00" +%s 2>/dev/null || date -jf "%Y-%m-%d %H:%M:%S" "$reboot_date 04:00:00" +%s 2>/dev/null)" ]; then
                        output="${output}\nErrors found but resolved by reboot: $error_sample"
                        # Don't count as an issue if there was a successful reboot after the errors
                    else
                        summary="${summary}\n- Recent errors in last upgrade: $error_sample"
                        issues_found=$((issues_found + 1))
                    fi
                else
                    summary="${summary}\n- Recent upgrade errors: $error_sample"
                    issues_found=$((issues_found + 1))
                fi
            else
                # This is an old error, don't count it as an issue
                output="${output}\nOld errors found (not counted as issues): $error_sample"
            fi
        fi
    fi

    # Check for pending updates
    local pending_updates=$(sudo apt-get --simulate upgrade 2>/dev/null | grep -c "^Inst")
    if [ "$pending_updates" -gt 10 ]; then
        summary="${summary}\n- Large number of pending updates ($pending_updates)"
        issues_found=$((issues_found + 1))
    else
        output="${output}\nPending updates: $pending_updates"
    fi
    
    # Check configuration files
    if [ ! -f /etc/apt/apt.conf.d/20auto-upgrades ] || [ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        summary="${summary}\n- Missing configuration files"
        issues_found=$((issues_found + 1))
    else
        # Check for key settings in config files
        if ! sudo grep -q "APT::Periodic::Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades; then
            summary="${summary}\n- Unattended upgrades not enabled in config"
            issues_found=$((issues_found + 1))
        fi
    fi

    # Summary
    if [ $issues_found -eq 0 ]; then
        echo "Auto-upgrades are properly configured and running"
        return 0
    else
        # Add the summary to verbose_output for the detailed report
        verbose_output="${verbose_output}\n\n--- AUTO-UPGRADES ISSUES ---$summary"
        
        # For the main output, just show the count of issues
        if [ $actions_taken -gt 0 ] && [ $actions_taken -eq $issues_found ]; then
            # All issues were fixed - return success
            echo "Auto-upgrades had $issues_found issues but all were auto-fixed"
            return 0
        else
            # Some issues remain - return a specific error message for run_check to display
            # with the red X
            # For Slack notifications, keep it brief
            echo "Auto-upgrades has $issues_found unresolved issues"
            return 1
        fi
    fi
}

# Run all checks
run_check "disk_space_root" "check_disk_space / 90"
run_check "disk_space_home" "check_disk_space /home 90"
run_check "memory_usage" "check_memory 90"
run_check "system_load" "check_system_load 2"
run_check "network_connectivity" "check_network"
run_check "auto_upgrades" "check_auto_upgrades"

# Create a summary message
echo "Completed system health checks at $(date)"

# Only show detailed output if there were issues
if [ $failed_checks -gt 0 ] && [ -n "$verbose_output" ]; then
    echo -e "\nDetailed diagnostics for failed checks:$verbose_output"
fi
# Exit with failure status if any checks failed
if [ $failed_checks -gt 0 ]; then
    exit 1
else
    exit 0
fi
