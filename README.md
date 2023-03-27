# raspberrypi-ansible
## Description
This is a collection of scripts to kickstart raspberry pi's using a minimal raspbian installation and deploy configurations using ansible playbooks

## Usage
This repo has multiple tools. Use at suited.
### Pre-bootup
- `load_rpi`:   MacOS tool to load a base image to an SD card
```
Usage: load_rpi image_source hostname
Parameters:
 image_source   Where to install the image from. Options: { netinstall | downloadurl | raspbian }
 hostname       Type of raspberry. Options: { pihole|cobra|hifipi|dockassist|devpi|vinylstreamer|pizero }
```
> Currently used `load_rpi raspbian [host]`

### Post-bootup
- `ansible-playbook installation.yml --limit=[host] -k --extra-vars "host=[host]"`: Ansible playbook to install a host. Note -k is only needed for the first run to add interactive initial password.
Requires:
- `python3 -m pip install --user ansible` - more info in [red hat docs](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html). Useful to have:
    - `python3 -m pip install --user argcomplete`
- `ansible-galaxy collection install community.crypto`
- `ansible-galaxy collection install ansible.posix`
- passlib - `pip install passlib`
- sshpass -- Deprecated, not needed anymore

# Flavours so far
## devpi
Barebones install for testing

## hifipi
This raspberry pi will use a [Hifiberry](https://www.hifiberry.com/) hat to play high quality audio received via Airplay using [shairport](https://github.com/mikebrady/shairport-sync) or Spotify connect via [raspotify](https://github.com/dtcooper/raspotify). It also runs [mpd](https://www.musicpd.org) and is used to play streams controlled by remote clients such as `vinylstreamer`
### TODO
- [ ] Find out how to monitor and restart raspotify/airplay receivers if not working

## Vinylstreamer
This raspberry pi will run an [icecast](https://icecast.org) server that exposes an internet-radio stream, fed by a [liquidsoap](https://www.liquidsoap.info) defined audiostream using ogg/flac. It will also run a python script `detect_audio.py` that will detect an input audio stream and remotely control an mpd daemon to play the icecast stream
### TODO
- [ ] Define on installation the remote ip to control mpd in `detect_audio.py`

## Cobra
TBD

## Pihole
TBD

## Dockassist
TBD

