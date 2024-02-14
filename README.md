# raspberrypi-ansible
## Description
This is a collection of scripts to flash an sd card from a MacOS laptop, and kickstart raspberry pi's using minimal raspbian installations and deploy configurations using ansible playbooks

## Usage
This repo has multiple tools. Use at suited.
### Pre-bootup - bash script
`load_rpi`:   MacOS tool to load a base image to an SD card
```
Usage: load_rpi image_source hostname
Parameters:
 image_source   Where to install the image from. Options: { netinstall | downloadurl | raspbian }
 hostname       Type of raspberry. Options: { pihole|cobra|hifipi|dockassist|devpi|vinylstreamer|pizero }
```
> Currently commonly used `load_rpi raspbian [host]`

### Post-bootup - ansible
#### Requisites
- `python3 -m pip install --user ansible` - more info in [red hat docs](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html). Useful to have:
    - `python3 -m pip install --user argcomplete`
- `ansible-galaxy collection install community.crypto`
- `ansible-galaxy collection install ansible.posix`
- passlib - `pip install passlib`
> Common problems arise with different python versions and ansible being available to specific versions

#### Usage
- `ansible-playbook installation.yml --limit=[host] -k --extra-vars "host=[host]"`: Ansible playbook to install a host. 
> Note -k is only needed for the first run to add interactive initial password.

#### Flavours so far
##### devpi
Barebones install for testing

##### hifipi
Streaming box thar uses a [hifiberry](https://www.hifiberry.com/) hat to play high quality audio received via Airplay using [shairport](https://github.com/mikebrady/shairport-sync) or Spotify connect via [raspotify](https://github.com/dtcooper/raspotify). It also runs [mpd](https://www.musicpd.org) and is used to play streams controlled by remote clients such as `vinylstreamer`
###### TODO
- [ ] Find out how to monitor and restart raspotify/airplay receivers if not working

##### Vinylstreamer
[Icecast](https://icecast.org) server that exposes an internet-radio stream, fed by a [liquidsoap](https://www.liquidsoap.info) defined audiostream using ogg/flac. It will also run a python script `detect_audio.py` that will detect an input audio stream and remotely control an mpd daemon to play the icecast stream
###### TODO
- [ ] Define on installation the remote ip to control mpd in `detect_audio.py`

##### Dockassist
Raspberry which will run homeassistant inside a dockercontainer

###### TODO
- [ ] Migrating from a previous installation is still manual. Procedure should be copying `/home/${USER}/homeassistant/` from the original host and then copy it to the same location and starting homeassistant to pick it up.

##### Cobra
This raspberry pi will contain a plex server (copying configurations from the previous existing server) and the necessary scripts to download automated torrents
It is expected for this script to work that the following files are available in the user home folder:
```
conf_auth.ini
conf_move.ini
```

###### TODO
- [ ] Migrating from a previous installation is stil manual. Procedure in the comments of the host playbook.

##### Pihole
TBD

