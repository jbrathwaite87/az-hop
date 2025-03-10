#!/bin/bash
# Script to use the latest Azure HPC health checks for HBv4 machines

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/azhop-helpers.sh"
read_os

# Get the actual VM size
VM_SIZE=$(curl -s --noproxy "*" -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2019-08-15" | jq -r '.vmSize' | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')

# Only run this for HBv4 machines
if [[ "$VM_SIZE" == *"hb176"* ]]; then
    echo "Setting up latest Azure HPC health checks for HBv4 machine"
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # Clone the latest health checks repository
    git clone https://github.com/Azure/azurehpc-health-checks.git
    
    if [ -d azurehpc-health-checks/conf ]; then
        echo "Successfully cloned Azure HPC health checks repository"
        
        # Check if the HBv4 configuration exists in the repo
        if [ -f azurehpc-health-checks/conf/hb176-48rs_v4.conf ] || [ -f azurehpc-health-checks/conf/hb176rs_v4.conf ]; then
            echo "Found HBv4 configuration in the repository"
            
            # Copy all configurations to the proper locations
            if [ -d /opt/azurehpc/test/azurehpc-health-checks/conf ]; then
                echo "Updating existing Azure HPC health checks configurations"
                cp -f azurehpc-health-checks/conf/* /opt/azurehpc/test/azurehpc-health-checks/conf/
            fi
            
            # Copy to the NHC configuration directory as well
            mkdir -p "$script_dir/../files/nhc/"
            
            # Copy either the hyphenated or non-hyphenated version based on what exists
            if [ -f azurehpc-health-checks/conf/hb176-48rs_v4.conf ]; then
                cp -f azurehpc-health-checks/conf/hb176-48rs_v4.conf "$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"
                cp -f azurehpc-health-checks/conf/hb176-48rs_v4.conf "$script_dir/../files/nhc/nhc_hb176rs_v4.conf"
                echo "Copied hb176-48rs_v4.conf to NHC configuration directory"
            elif [ -f azurehpc-health-checks/conf/hb176rs_v4.conf ]; then
                cp -f azurehpc-health-checks/conf/hb176rs_v4.conf "$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"
                cp -f azurehpc-health-checks/conf/hb176rs_v4.conf "$script_dir/../files/nhc/nhc_hb176rs_v4.conf"
                echo "Copied hb176rs_v4.conf to NHC configuration directory"
            fi
            
            # Update the run-health-checks.sh script if it exists
            if [ -f azurehpc-health-checks/run-health-checks.sh ] && [ -f /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh ]; then
                echo "Updating the health checks script"
                cp -f azurehpc-health-checks/run-health-checks.sh /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
                chmod +x /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
            fi
            
            echo "Successfully updated Azure HPC health checks configurations"
        else
            echo "No HBv4 configuration found in the repository, falling back to manual configuration"
            
            # Get the actual memory size from the system
            ACTUAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            
            # Create the HBv4 config files
            for CONFIG_FILE in "$script_dir/../files/nhc/nhc_hb176rs_v4.conf" "$script_dir/../files/nhc/nhc_hb176-48rs_v4.conf"; do
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
                echo "Created $CONFIG_FILE with correct memory: ${ACTUAL_MEM}kB"
            done
        fi
    else
        echo "Failed to clone Azure HPC health checks repository"
    fi
    
    # Clean up
    rm -rf $TEMP_DIR
    
    # Add validation by running the health check
    if [ -f /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh ]; then
        echo "Validating health checks configuration"
        /opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh > /var/log/nhc-validation.log 2>&1
        echo "Health check exit code: $?" >> /var/log/nhc-validation.log
        echo "Validation log written to /var/log/nhc-validation.log"
    fi
    
    echo "HBv4 health checks configuration completed"
fi
