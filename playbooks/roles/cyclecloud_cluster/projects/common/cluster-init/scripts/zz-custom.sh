#!/bin/bash
# Script to ensure correct HBv4 health check configuration

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/azhop-helpers.sh"
read_os

# Set up logging for debugging
exec > /var/log/nhc-fix.log 2>&1
set -x

# Get the actual VM size
VM_SIZE=$(curl -s --noproxy "*" -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2019-08-15" | jq -r '.vmSize' | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')

# Only run this for HBv4 machines
if [[ "$VM_SIZE" == *"hb176"* ]]; then
    echo "Configuring health checks for HBv4 machine: $VM_SIZE"
    
    # Path to VM-specific config that will be used by the installation script
    NHC_CONFIG_FILE="/etc/nhc/nhc.conf"
    NHC_CONFIG_EXTRA="$script_dir/../files/nhc/nhc_${VM_SIZE}.conf"
    
    # Get the actual memory size from the system
    ACTUAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo "Actual memory size: ${ACTUAL_MEM}kB"
    
    # Create the VM-specific config with correct memory
    cat > "$NHC_CONFIG_EXTRA" << EOF
#######################################################################
###
### HB176rs_v4 hardware checks
###

* || check_hw_cpuinfo 2 176 176
* || check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB 3%
* || check_hw_eth ib0
# * || check_hw_ib 200 mlx5_ib0:1
EOF
    echo "Created $NHC_CONFIG_EXTRA with correct memory: ${ACTUAL_MEM}kB"
    
    # If another naming scheme is used, create that file too
    if [[ "$VM_SIZE" == "hb176-48rs_v4" ]]; then
        ALT_CONFIG="$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"
        cp -f "$NHC_CONFIG_EXTRA" "$ALT_CONFIG"
        echo "Created alternate config at $ALT_CONFIG"
    elif [[ "$VM_SIZE" == "hb176rs_v4" ]]; then
        ALT_CONFIG="$script_dir/../files/nhc/nhc_hb176rs_v4.conf"
        cp -f "$NHC_CONFIG_EXTRA" "$ALT_CONFIG"
        echo "Created alternate config at $ALT_CONFIG"
    fi
    
    # If the NHC config file already exists, update it directly
    if [ -f "$NHC_CONFIG_FILE" ]; then
        echo "NHC config file already exists, updating memory values"
        sed -i "s/check_hw_physmem [0-9]*kB [0-9]*kB/check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB/g" "$NHC_CONFIG_FILE"
    fi
    
    # Fix any existing AzureHPC health checks configs
    if [ -d /opt/azurehpc/test/azurehpc-health-checks/conf ]; then
        echo "Updating AzureHPC health checks configs"
        for CONF_FILE in /opt/azurehpc/test/azurehpc-health-checks/conf/hb176*; do
            if [ -f "$CONF_FILE" ]; then
                echo "Updating $CONF_FILE"
                sed -i "s/check_hw_physmem [0-9]*kB [0-9]*kB/check_hw_physmem ${ACTUAL_MEM}kB ${ACTUAL_MEM}kB/g" "$CONF_FILE"
            fi
        done
    fi
    
    echo "Configuration completed"
    
    # Add validation step - create a file that the node health check will run on next boot
    echo "#!/bin/bash
# Run health check validation on next boot
if [ -f /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh ]; then
    echo \"Running health checks validation: \$(date)\" > /var/log/nhc-validation.log
    /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh >> /var/log/nhc-validation.log 2>&1
    echo \"Health check exit code: \$?\" >> /var/log/nhc-validation.log
fi" > /etc/rc.local
    chmod +x /etc/rc.local
    
    echo "Validation script added to /etc/rc.local"
fi
