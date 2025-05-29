#!/bin/bash
# external_host_monitor.sh - Monitor hosts and alert if they're unresponsive
# 
# This script performs tailored connectivity and service checks on raspberry pi hosts
# and sends alerts when issues are detected.

set -o pipefail

# Set default values
SCRIPT_NAME="external_host_monitor"
ALERT=true
LOGGING=true
EMAIL=false
SILENT=false
RECIPIENT=""

# Parse command line arguments (compatible with enhanced_monitoring_wrapper)
while [[ $# -gt 0 ]]; do
  case $1 in
    --alert)
      ALERT=true
      shift
      ;;
    --no-alert)
      ALERT=false
      shift
      ;;
    --logging)
      LOGGING=true
      shift
      ;;
    --no-logging)
      LOGGING=false
      shift
      ;;
    --email)
      EMAIL=true
      RECIPIENT="$2"
      shift 2
      ;;
    --silent)
      SILENT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to log messages
log_message() {
  local level="$1"
  local message="$2"
  
  if [[ "$LOGGING" == "true" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
  fi
  
  if [[ "$SILENT" != "true" && "$LOGGING" != "true" ]]; then
    echo "[$level] $message"
  fi
}

# Function to send alerts
send_alert() {
  local host="$1"
  local ip="$2"
  local issue="$3"
  local message="HOST DOWN: $host ($ip) - $issue"
  
  log_message "ALERT" "$message"
  
  if [[ "$ALERT" == "true" ]]; then
    # Integration with enhanced_monitoring_wrapper
    echo "ISSUE DETECTED: $message"
  fi
  
  if [[ "$EMAIL" == "true" && -n "$RECIPIENT" ]]; then
    echo "$message" | mail -s "HOST DOWN: $host ($ip)" "$RECIPIENT"
  fi
}

# Function to send recovery notifications
send_recovery() {
  local host="$1"
  local ip="$2"
  local message="HOST RECOVERED: $host ($ip) is back online"
  
  log_message "RECOVERY" "$message"
  
  if [[ "$ALERT" == "true" ]]; then
    # Integration with enhanced_monitoring_wrapper
    echo "ISSUE FIXED: $message"
  fi
  
  if [[ "$EMAIL" == "true" && -n "$RECIPIENT" ]]; then
    echo "$message" | mail -s "HOST RECOVERED: $host ($ip)" "$RECIPIENT"
  fi
}

# Function to check if host is responding to ping
check_ping() {
  local host="$1"
  local count=3
  local timeout=2
  
  ping -c $count -W $timeout "$host" > /dev/null 2>&1
  return $?
}

# Function to check if port is open
check_port() {
  local host="$1"
  local port="$2"
  local timeout=5
  
  nc -z -w $timeout "$host" "$port" > /dev/null 2>&1
  return $?
}

# Function to check DNS resolution (for pihole)
check_dns() {
  local host="$1"
  local domain="google.com"
  
  dig @"$host" "$domain" +short +timeout=5 > /dev/null 2>&1
  return $?
}

# Function to resolve hostname to IP address
resolve_ip() {
  local hostname="$1"
  local ip
  
  # Check if we're on Linux and have getent available
  if command -v getent >/dev/null 2>&1 && [[ "$(uname)" == "Linux" ]]; then
    # Use getent on Linux systems
    ip=$(getent hosts "$hostname" | awk '{ print $1 }')
  else
    # For macOS and other systems without getent, use dig/host
    if command -v dig >/dev/null 2>&1; then
      ip=$(dig +short "$hostname" | head -n1)
    elif command -v host >/dev/null 2>&1; then
      ip=$(host "$hostname" | grep 'has address' | head -n1 | awk '{print $NF}')
    fi
  fi
  
  echo "$ip"
}

# Check specific host with tailored checks
check_host() {
  local hostname="$1"
  local status_file="/tmp/host_status_${hostname}"
  local was_down=false
  local is_down=false
  local issues=()
  local ip
  
  # Resolve hostname to IP
  ip=$(resolve_ip "$hostname")
  if [[ -z "$ip" ]]; then
    log_message "WARNING" "Could not resolve IP for $hostname"
    ip="unknown"
  fi
  
  log_message "INFO" "Checking host $hostname ($ip)"
  
  # Check if host was previously down
  if [[ -f "$status_file" ]]; then
    was_down=true
  fi
  
  # Basic ping check for all hosts
  if ! check_ping "$hostname"; then
    is_down=true
    issues+=("Failed to respond to ping")
  else
    # SSH check for all hosts
    if ! check_port "$hostname" 22; then
      issues+=("SSH port not accessible")
    fi
    
    # Host-specific checks only if ping succeeds
    case "$hostname" in
      pihole)
        # DNS service check
        if ! check_dns "$hostname"; then
          issues+=("DNS service not responding")
        fi
        # Web interface check
        if ! check_port "$hostname" 80; then
          issues+=("Web interface not accessible")
        fi
        ;;
        
      cobra)
        # Basic HTTP check for Transmission web interface - most likely to be exposed
        if ! check_port "$hostname" 9091; then
          issues+=("Transmission web interface not accessible")
        fi
        # Only check Samba if this is an internal network check
        # Samba is often blocked at the firewall level externally
        if [[ "$ip" == 10.* || "$ip" == 192.168.* ]]; then
          if ! check_port "$hostname" 445; then
            issues+=("Samba service not accessible")
          fi
        fi
        ;;
        
      hifipi)
        # Basic connectivity check is sufficient - audio services may not be externally exposed
        # MPD is often configured to only listen on localhost
        log_message "INFO" "Basic connectivity check passed for $hostname"
        ;;
        
      dockassist)
        # Basic connectivity check for Home Assistant
        # Don't check content - just verify the port is open
        if ! check_port "$hostname" 8123; then
          issues+=("Home Assistant web interface not accessible")
        fi
        ;;
        
      vinylstreamer)
        # Check if Icecast port is open, but don't validate content
        if ! check_port "$hostname" 8000; then
          issues+=("Icecast streaming port not accessible")
        fi
        # MPD is likely only listening on localhost or requires authentication
        log_message "INFO" "Basic connectivity and Icecast port check for $hostname"
        ;;
        
      devpi | pizero)
        # Basic connectivity check already done with ping and SSH
        log_message "INFO" "Basic checks completed for $hostname"
        ;;
        
      *)
        log_message "WARNING" "Unknown host type: $hostname, only basic checks performed"
        ;;
    esac
  fi
  
  # Set host status based on issues
  if [[ ${#issues[@]} -gt 0 ]]; then
    is_down=true
  fi
  
  # Handle status changes and notifications
  if [[ "$is_down" == "true" ]]; then
    if [[ "$was_down" == "false" ]]; then
      # Host just went down
      send_alert "$hostname" "$ip" "${issues[*]}"
      touch "$status_file"
    fi
  else
    if [[ "$was_down" == "true" ]]; then
      # Host recovered
      send_recovery "$hostname" "$ip"
      rm -f "$status_file"
    fi
    log_message "INFO" "Host $hostname ($ip) is UP"
  fi
}

# Main function
main() {
  log_message "INFO" "Starting external host monitoring on $(date '+%Y-%m-%d %H:%M:%S')"
  
  # List of hosts to monitor - dynamically get from DNS or inventory
  HOSTS=("pihole" "cobra" "hifipi" "dockassist" "vinylstreamer")
  
  # Check each host
  for host in "${HOSTS[@]}"; do
    # Try to resolve the host
    ip=$(resolve_ip "$host")
    if [[ -z "$ip" || "$ip" == "unknown" ]]; then
      # Host cannot be resolved - this is a problem worth alerting on
      log_message "ALERT" "Host $host cannot be resolved in DNS"
      if [[ "$ALERT" == "true" ]]; then
        echo "ISSUE DETECTED: Host $host cannot be resolved in DNS - check DNS configuration"
      fi
    else
      check_host "$host"
    fi
  done
  
  # Print summary information
  echo ""
  log_message "INFO" "External host monitoring completed at $(date '+%Y-%m-%d %H:%M:%S')"
  log_message "INFO" "Monitored hosts: ${HOSTS[*]}"
  
  # Check if any hosts are in a down state
  down_count=0
  for host in "${HOSTS[@]}"; do
    if [[ -f "/tmp/host_status_${host}" ]]; then
      ((down_count++))
    fi
  done
  
  if [[ $down_count -gt 0 ]]; then
    log_message "WARNING" "$down_count hosts currently have issues"
  else
    log_message "INFO" "All hosts are operating normally"
  fi
}

# Run the main function
main
