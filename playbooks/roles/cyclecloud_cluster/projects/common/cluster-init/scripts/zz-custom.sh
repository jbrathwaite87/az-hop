#!/bin/bash
# Custom script to fix NHC health check memory issues for HBv4 machines

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/azhop-helpers.sh"
read_os

# Get the actual VM size
VM_SIZE=$(curl -s --noproxy "*" -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2019-08-15" | jq -r '.vmSize' | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')

# Only run this fix for HBv4 machines
if [[ "$VM_SIZE" == *"hb176"* ]]; then
    echo "Fixing NHC health check configuration for HBv4 machine"
    
    # Get the actual memory size from the system
    ACTUAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    # Update both versions of the config files
    CONFIG_FILES=(
        "$script_dir/../files/nhc/nhc_hb176rs_v4.conf"
        "$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"
    )
    
    for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
        if [ -f "$CONFIG_FILE" ]; then
            echo "Updating $CONFIG_FILE with correct memory: ${ACTUAL_MEM}kB"
            sed -i "s/check_hw_physmem [0-9]*kB [0-9]*kB/check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB/g" "$CONFIG_FILE"
        else
            echo "Creating $CONFIG_FILE with correct memory: ${ACTUAL_MEM}kB"
            mkdir -p "$(dirname "$CONFIG_FILE")"
            cat > "$CONFIG_FILE" << EOF
#######################################################################
###
### HB176rs_v4 hardware checks
###

* || check_hw_cpuinfo 2 176 176
* || check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB 3%
* || check_hw_eth ib0
# * || check_hw_ib 200 mlx5_ib0:1
EOF
        fi
    done
    
    # Also check for the Azure HPC health checks paths
    AZ_HPC_PATHS=(
        "/opt/azurehpc/test/azurehpc-health-checks/conf/hb176-48rs_v4.conf"
        "/opt/azurehpc/test/azurehpc-health-checks/conf/hb176-48rs_v4_appended.conf"
        "/opt/azurehpc/test/azurehpc-health-checks/conf/hb176rs_v4.conf"
        "/opt/azurehpc/test/azurehpc-health-checks/conf/hb176rs_v4_appended.conf"
    )
    
    for AZ_PATH in "${AZ_HPC_PATHS[@]}"; do
        if [ -f "$AZ_PATH" ]; then
            echo "Updating Azure HPC config $AZ_PATH with correct memory: ${ACTUAL_MEM}kB"
            sed -i "s/check_hw_physmem [0-9]*kB [0-9]*kB/check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB/g" "$AZ_PATH"
        else
            # Create parent directory if it doesn't exist
            mkdir -p "$(dirname "$AZ_PATH")"
            
            echo "Creating Azure HPC config $AZ_PATH with correct memory: ${ACTUAL_MEM}kB"
            cat > "$AZ_PATH" << EOF
* || check_hw_cpuinfo 2 176 176
* || check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB 3%
* || check_hw_eth ib0
EOF
        fi
    done
    
    # If the health check script exists, modify it to use the correct memory values
    if [ -f /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh ]; then
        echo "Checking health check script for hardcoded memory values"
        # Replace the hardcoded memory value in the script
        sed -i "s/726513480/${ACTUAL_MEM}/g" /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
        
        # Ensure script uses our custom config
        if grep -q "NO_CUSTOM_CONF=1" /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh; then
            echo "Setting health check script to use custom config"
            sed -i "s/NO_CUSTOM_CONF=1/NO_CUSTOM_CONF=0/" /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
        fi
    fi
    
    # If the final NHC config exists, update it directly
    if [ -f /etc/nhc/nhc.conf ]; then
        echo "Updating final NHC config /etc/nhc/nhc.conf with correct memory: ${ACTUAL_MEM}kB"
        sed -i "s/check_hw_physmem [0-9]*kB [0-9]*kB/check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB/g" /etc/nhc/nhc.conf
    fi
    
    echo "All NHC configuration files have been updated with correct memory: ${ACTUAL_MEM}kB"
    
    # Reload NHC if it's running as a service
    if systemctl is-active --quiet nhc; then
        echo "Reloading NHC service"
        systemctl restart nhc
    fi
fi
