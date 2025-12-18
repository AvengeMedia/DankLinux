#!/bin/bash
# Upload OBS project configuration
osc meta prjconf home:AvengeMedia:danklinux -F distro/obs-project.conf
echo "Project configuration updated on OBS"
