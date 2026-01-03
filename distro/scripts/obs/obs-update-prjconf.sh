#!/bin/bash
# Upload OBS project configuration for home:AvengeMedia:danklinux
# Usage: ./distro/scripts/obs/obs-update-prjconf.sh

# Get script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$REPO_ROOT"

if [[ ! -f "distro/obs-project.conf" ]]; then
    echo "Error: distro/obs-project.conf not found"
    echo "       Run this script from the repository root"
    exit 1
fi

echo "==> Updating OBS project configuration..."
echo "    Project: home:AvengeMedia:danklinux"
echo "    Config file: distro/obs-project.conf"
echo ""

osc meta prjconf home:AvengeMedia:danklinux -F distro/obs-project.conf

if [[ $? -eq 0 ]]; then
    echo ""
    echo "✅ Project configuration updated on OBS"
    echo ""
else
    echo ""
    echo "❌ Failed to update project configuration"
    exit 1
fi
