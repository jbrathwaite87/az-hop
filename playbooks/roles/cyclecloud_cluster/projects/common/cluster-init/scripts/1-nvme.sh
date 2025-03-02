#!/bin/bash
NVME_DISKS_NAME=`ls /dev/nvme*n1 2>/dev/null || echo ""`
NVME_DISKS=`ls -latr /dev/nvme*n1 2>/dev/null | wc -l`
echo "Number of NVMe Disks: $NVME_DISKS"

if [ "$NVME_DISKS" == "0" ]
then
  echo "No NVMe disks found, exiting."
  exit 0
else
  mkdir -p /mnt/nvme
  
  # Stop any existing MD arrays safely
  if ls /dev/md* &>/dev/null; then
    mdadm --stop /dev/md* 2>/dev/null || true
  fi
  
  # Use a name format that works better with mdadm
  RAID_DEV="/dev/md0"
  
  # Create the RAID array with proper error handling
  echo "Creating RAID0 array with $NVME_DISKS disks: $NVME_DISKS_NAME"
  mdadm --create $RAID_DEV --level=0 --raid-devices=$NVME_DISKS $NVME_DISKS_NAME --force --run
  
  # Check if RAID creation was successful
  if [ $? -ne 0 ]; then
    echo "Failed to create RAID array. Exiting."
    exit 1
  fi
  
  # Wait a moment for the device to stabilize
  sleep 2
  
  # Format the array
  echo "Formatting $RAID_DEV with XFS filesystem"
  mkfs.xfs -f $RAID_DEV
  
  # Mount the filesystem
  echo "Mounting $RAID_DEV to /mnt/nvme"
  mount $RAID_DEV /mnt/nvme || {
    echo "Mount failed. Exiting."
    exit 1
  }
  
  # Set permissions
  chmod 1777 /mnt/nvme
  echo "NVMe RAID setup complete - mounted at /mnt/nvme"
fi
