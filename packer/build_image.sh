#!/bin/bash
# Build an image with packer and the provided packer file
# There are 2 options for providing the SPN used by packer:
#  - With environment variables (e.g., in GitHub Actions: ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID)
#  - Through the spn.json config file

set -e
set -o pipefail
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OPTIONS_FILE=options.json
FORCE=0
#SPN_FILE=spn.json
CONFIG_FILE=../config.yml
ANSIBLE_VARIABLES=../playbooks/group_vars/all.yml

if [ $# -lt 2 ]; then
  echo "Usage: build_image.sh -i|--image <image_file.json> [options]"
  echo "  Required arguments:"
  echo "    -i|--image <image_file.json> | image packer file"
  echo "  Optional arguments:"
  echo "    -o|--options <options.json>  | file with options for packer generated in the build phase"
  echo "    -f|--force                   | overwrite existing image and always push a new version in the SIG"
  echo "    -k|--keep                    | keep OS disk for future reuse"
  exit 1
fi

load_miniconda() {
  # Package inside a function to avoid forwarding arguments to conda
  if [ -d "${THIS_DIR}/../miniconda" ]; then
    echo "Activating conda environment"
    source "${THIS_DIR}/../miniconda/bin/activate"
  fi
}

load_miniconda
# Check config syntax
yamllint "$CONFIG_FILE"

PACKER_OPTIONS="-timestamp-ui"
KEEP_OS_DISK="false"

while (( "$#" )); do
  case "${1}" in
    -i|--image)
      PACKER_FILE=${2}
      shift 2
    ;;
    -o|--options)
      OPTIONS_FILE=${2}
      shift 2
    ;;
    -f|--force)
      FORCE=1
      PACKER_OPTIONS+=" -force"
      shift 1
    ;;
    -k|--keep)
      KEEP_OS_DISK="true"
      shift 1
    ;;
    *)
      shift
      ;;
  esac
done

if [ ! -f "${PACKER_FILE}" ]; then
  echo "Packer file ${PACKER_FILE} not found"
  exit 1
fi

# Determine image name from the packer file
image_name=$(basename "$PACKER_FILE")
image_name="${image_name%.*}"
# Use the correct resource group (as per build output)
resource_group="dev-apqx-azhop-rg"

# Generate install script checksum
set +e
script_dir=$(jq -r '.provisioners[0].source' "$PACKER_FILE")
find "$script_dir" -exec md5sum {} \; > md5sum.txt
md5sum "$PACKER_FILE" >> md5sum.txt
set -e
packer_md5=$(md5sum md5sum.txt | cut -d' ' -f 1)
echo "scripts checksum is $packer_md5"

# Retrieve the current Image ID (if any)
image_id=$(az image list -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
if [ -n "$image_id" ]; then
  image_checksum=$(az image show --id "$image_id" --query "tags.checksum" -o tsv)
  echo "Existing image checksum is $image_checksum"
  if [ "$packer_md5" != "$image_checksum" ]; then
    FORCE=1
    PACKER_OPTIONS+=" -force"
  fi
fi

# If FORCE is set and an image exists, delete it before building a new one
if [ -n "$image_id" ] && [ $FORCE -eq 1 ]; then
  echo "Force flag is set. Deleting existing managed image: $image_name"
  az image delete --ids "$image_id" -o tsv
  image_id=""
fi


# Build a new image if the image does not exist (or was deleted) or FORCE is set
if [ -z "$image_id" ] || [ $FORCE -eq 1 ]; then
  logfile="${PACKER_FILE%.*}.log"
  
  # Determine cloud environment
  cloud_env="Public"
  account_env=$(az account show | jq -r '.environmentName')
  case "$account_env" in
    AzureUSGovernment)
      cloud_env="USGovernment"
      ;;
    AzureCloud)
      cloud_env="Public"
      ;;
    *)
      cloud_env="Public"
      ;;
  esac
  
  echo "Building/Rebuilding $image_name in $resource_group (log: $logfile)"
  key_vault_name=$(yq eval ".key_vault" "$ANSIBLE_VARIABLES")
  
  echo "Removing OS disk if any..."
  os_disk_id=$(az disk list -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
  if [ -n "$os_disk_id" ]; then
    az disk delete --ids "$os_disk_id" -o tsv -y
  fi
  
  packer plugins install github.com/hashicorp/azure
  
  packer build $PACKER_OPTIONS -var-file "$OPTIONS_FILE" \
    -var "var_use_azure_cli_auth=$use_azure_cli_auth" \
    -var "var_image=$image_name" \
    -var "var_img_version=$version" \
    -var "var_cloud_env=$cloud_env" \
    -var "var_key_vault_name=$key_vault_name" \
    -var "var_keep_os_disk=$KEEP_OS_DISK" \
    "$PACKER_FILE" | tee "$logfile"
  
  # Retrieve the new image ID after build
  image_id=$(az image list -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
  if [ -z "$image_id" ]; then
    echo "❌ ERROR: Image ID is empty after build."
    exit 1
  else
    echo "✅ Found Image ID after build: $image_id"
  fi
  
  # Tag the newly built image with the checksum
  echo "Tagging the source image with checksum $packer_md5"
  az image update --ids "$image_id" --tags checksum="$packer_md5" -o tsv
else
  echo "Image $image_name exists, skipping build."
fi

# --- Ensure Image Gallery Exists with a Unique Name ---
# --- Ensure Image Gallery Exists with a Unique Name ---
base_gallery_name="aps_image_gallery"
# Check if a gallery with the base name exists in the resource group
existing_gallery=$(az sig gallery list --resource-group "$resource_group" --query "[?name=='$base_gallery_name'].name" -o tsv)
if [ -z "$existing_gallery" ]; then
  # Create a unique gallery name by appending a UTC timestamp
  timestamp=$(date -u +"%Y%m%d%H%M%S")
  sig_name="${base_gallery_name}-${timestamp}"
  echo "Image gallery not found. Creating new image gallery: $sig_name"
  az sig gallery create \
    --gallery-name "$sig_name" \
    --resource-group "$resource_group" \
    --location eastus \
    --description "Gallery created by build_image.sh" \
    --permissions Private
else
  sig_name="$base_gallery_name"
  echo "Image gallery $sig_name exists."
fi


# Create the image definition in the SIG if it doesn't exist
img_def_id=$(az sig image-definition list -r "$sig_name" -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
if [ -z "$img_def_id" ]; then
  echo "Creating an image definition for $image_name"
  echo "Reading image definition from $CONFIG_FILE"
  eval_str=".images[] | select(.name == "\"$image_name"\") | .offer"
  offer=$(yq eval "$eval_str" "$CONFIG_FILE")
  eval_str=".images[] | select(.name == "\"$image_name"\") | .publisher"
  publisher=$(yq eval "$eval_str" "$CONFIG_FILE")
  eval_str=".images[] | select(.name == "\"$image_name"\") | .sku"
  sku=$(yq eval "$eval_str" "$CONFIG_FILE")
  eval_str=".images[] | select(.name == "\"$image_name"\") | .hyper_v"
  hyper_v=$(yq eval "$eval_str" "$CONFIG_FILE")
  if [ -z "$hyper_v" ]; then 
    hyper_v="V1"
  fi
  eval_str=".images[] | select(.name == "\"$image_name"\") | .os_type"
  os_type=$(yq eval "$eval_str" "$CONFIG_FILE")
  
  az sig image-definition create -r "$sig_name" -i "$image_name" -g "$resource_group" \
                -f "$offer" --os-type "$os_type" -p "$publisher" -s "$sku" --hyper-v-generation "$hyper_v" \
                --query 'id' -o tsv
  img_def_id=$(az sig image-definition list -r "$sig_name" -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
else
  echo "Image definition for $image_name found in gallery $sig_name"
fi

# Check if the managed image version exists in the SIG; if not, push a new version
image_id=$(az image list -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
image_version=$(az image show --id "$image_id" --query "tags.Version" -o tsv)
echo "Looking for image $image_name version $image_version ..."
img_version_id=$(az sig image-version list -r "$sig_name" -i "$image_name" -g "$resource_group" --query "[?name=='$image_version'].id" -o tsv)

if [ -z "$img_version_id" ] || [ $FORCE -eq 1 ]; then
  # Image version is YYY.MMDD.HHMM
  version=$(date -u +"%Y.%m%d.%H%M")
  echo "Pushing version $version of $image_name in $sig_name"
  
  storage_type=$(az image show --id "$image_id" --query "storageProfile.osDisk.storageAccountType" -o tsv)
  location=$(jq -r '.var_location' "$OPTIONS_FILE")
  
  az sig image-version create \
    --resource-group "$resource_group" \
    --gallery-name "$sig_name" \
    --gallery-image-definition "$image_name" \
    --gallery-image-version "$version" \
    --storage-account-type "$storage_type" \
    --location "$location" \
    --replica-count 1 \
    --managed-image "$image_id" \
    -o tsv
  
  echo "Tagging the source image with version $version and checksum $packer_md5"
  az image update --ids "$image_id" --tags Version="$version" checksum="$packer_md5" -o tsv
  
  if [ "$KEEP_OS_DISK" == "true" ]; then
    echo "Tagging the OS disk with version $version"
    os_disk_id=$(az disk list -g "$resource_group" --query "[?name=='$image_name'].id" -o tsv)
    az disk update --ids "$os_disk_id" --set tags.'Version'="$version" -o tsv
  fi
else
  echo "Image $image_name version $image_version found in gallery $sig_name"
fi
