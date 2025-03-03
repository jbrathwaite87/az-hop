#!/bin/bash
set -e  # Exit on error
set -x  # Print each command for debugging

# Automatically find the latest available Lustre version
LATEST_VERSION=$(apt-cache madison amlfs-lustre-client | awk '{print $3}' | head -n 1)

if [ -z "$LATEST_VERSION" ]; then
    echo "❌ ERROR: No available version found for amlfs-lustre-client!"
    exit 1
fi

echo "✅ Installing Lustre Client Version: $LATEST_VERSION"

# Add the Lustre repo
source /etc/lsb-release
echo "deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-${DISTRIB_CODENAME}/ ${DISTRIB_CODENAME} main" | sudo tee /etc/apt/sources.list.d/amlfs.list
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg

# Update package lists
sudo apt-get update

# Install the latest available version
sudo apt-get install -y "amlfs-lustre-client=$LATEST_VERSION"
