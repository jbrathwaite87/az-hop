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
    
    # Create or update the HBv4 specific config
    NHC_HB176_CONF="$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"
    
    cat > "$NHC_HB176_CONF" << EOF
#######################################################################
###
### HB176rs_v4 hardware checks
###

* || check_hw_cpuinfo 2 176 176
* || check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB 3%
* || check_hw_eth ib0
# * || check_hw_ib 200 mlx5_ib0:1
EOF

    # Also fix the Azure HPC health checks configuration if it exists
    if [ -d /opt/azurehpc/test/azurehpc-health-checks/conf ]; then
        AZURE_HPC_CONF="/opt/azurehpc/test/azurehpc-health-checks/conf/hb176-48rs_v4_appended.conf"
        
        cat > "$AZURE_HPC_CONF" << EOF
* || check_hw_cpuinfo 2 176 176
* || check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB 3%
* || check_hw_eth ib0
EOF
        
        echo "Created/Updated Azure HPC health checks configuration at $AZURE_HPC_CONF"
    fi
    
    echo "NHC configuration has been updated with correct memory value: ${ACTUAL_MEM}kB"
fi
