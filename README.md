# Raspberry Pi Ansible

A comprehensive toolkit for deploying and managing Raspberry Pi devices with Ansible. This project provides tools for both initial SD card setup and post-boot configuration management.

## Quick Start

### 1. Pre-Boot Setup (MacOS)

Flash an SD card with a base Raspbian image:

```bash
./load_rpi raspbian [hostname]
```

Where `[hostname]` is one of: `pihole`, `cobra`, `hifipi`, `dockassist`, `devpi`, `vinylstreamer`, or `pizero`.

### 2. Initial Configuration

Before running Ansible, create your configuration:

```bash
cp group_vars/all.yaml.sample group_vars/all.yaml
```

Edit `all.yaml` with your specific settings (GitHub profile, Slack tokens, etc.).

### 3. Run Ansible Playbook

```bash
ansible-playbook installation.yml --limit=[hostname] -k --extra-vars "host=[hostname]"
```

The `-k` flag is only needed for the first run to provide the initial SSH password.

## System Requirements

### Control Machine (Your Computer)

- Python 3
- Ansible: `python3 -m pip install --user ansible`
- Required collections:
  ```bash
  ansible-galaxy collection install community.crypto
  ansible-galaxy collection install community.general
  ansible-galaxy collection install ansible.posix
  ```
- Passlib: `pip install passlib`

## Project Structure

```
├── common_playbooks/     # Reusable playbooks for common tasks
├── common_scripts/       # Scripts deployed to all Raspberry Pis
├── group_vars/           # Global variables for all hosts
├── host_playbooks/       # Host-specific playbooks and configurations
├── installation.yml      # Main playbook that orchestrates the entire setup
└── load_rpi              # MacOS tool to flash SD cards
```

## Core Features

- **Modular Design**: Common tasks are separated into reusable playbooks
- **Enhanced Monitoring**: Intelligent monitoring system with self-healing capabilities
- **Security Hardening**: SSH hardening, user security, and more
- **Host-Specific Configurations**: Specialized setups for different use cases

## Monitoring System

The project includes a monitoring system that can:

- Monitor services and restart them if they fail
- Check disk usage and other system resources
- Send notifications via Slack webhooks
- Log activities and self-healing actions

To add monitoring to a host-specific playbook:

```yaml
- name: Import deploy monitoring
  ansible.builtin.import_playbook: "../common_playbooks/deploy_monitoring.yml"
  vars:
    monitoring_name: "service_name"
    monitoring_script_src: "path/to/script.sh"
    cron_minute: "*/5"
```

## Host Types

### devpi
Minimal installation used for testing and development.

### pihole
Network-wide ad blocking solution with DNS management capabilities. It also contains a unifi controller installation.

### hifipi
High-quality audio streaming device using a HifiBerry HAT. Supports:
- Airplay via Shairport
- Spotify Connect via Raspotify
- MPD for remote-controlled streaming

### vinylstreamer
Icecast server that streams audio using Liquidsoap. Features:
- OGG/FLAC audio streaming
- Audio detection script for remote MPD control

### dockassist
Docker-based Home Assistant installation for home automation.

### cobra
Media server and torrent management system featuring:
- Plex media server
- Automated torrent downloading

## Troubleshooting

- **SSH Connection Issues**: Ensure the Raspberry Pi is on the network and SSH is enabled
- **Ansible Errors**: Check Python version compatibility between control machine and Raspberry Pi
- **Variable Errors**: Verify all required variables are defined in your `group_vars/all.yaml`

## Migration Notes

- **dockassist**: Copy `/home/${USER}/homeassistant/` from original host to new installation
- **cobra**: See host playbook comments for migration procedure
