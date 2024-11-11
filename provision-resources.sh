#!/bin/bash

# Check if cloud is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <cloud> [region]"
  echo "Cloud options: aws, azure"
  echo "Region (optional, defaults to 'us-west-2' for AWS and 'eastus' for Azure)"
  exit 1
fi

# Set the cloud environment based on input
CLOUD=$1
echo "Provisioning resources for cloud: $CLOUD"

# Generate SSH Key Pair
ssh_key_path=$(pwd)/private_key.pem
TF_VAR_ssh_public_key="${ssh_key_path}.pub"
ssh-keygen -t rsa -b 2048 -f $ssh_key_path -N ""
export TF_VAR_ssh_public_key

# Set cloud-specific variables
if [ "$CLOUD" == "aws" ]; then
  # Retrieve the active Capacity Reservation ID
  REGION=${2:-us-west-2}
  export TF_VAR_region="$REGION"
  TF_VAR_capacity_reservation_id=$(aws ec2 describe-capacity-reservations \
    --region $REGION \
    --filters Name=state,Values=active \
    --query "CapacityReservations[0].[CapacityReservationId]" \
    --output text)

  # Check if the Capacity Reservation ID and Zone were retrieved successfully
  if [ "$TF_VAR_capacity_reservation_id" == "None" ] || [ -z "$TF_VAR_capacity_reservation_id" ]; then
    echo "No active capacity reservation found in AWS."
    exit 1
  fi

  export TF_VAR_capacity_reservation_id
  export TF_VAR_zone_suffix="a"

elif [ "$CLOUD" == "azure" ]; then
  REGION=${2:-eastus2}
  export TF_VAR_region=$REGION
else
  echo "Invalid cloud: $CLOUD. Please use 'aws' or 'azure'."
  exit 1
fi

# Set general variables
export TF_VAR_owner=$(whoami)
export TF_VAR_run_id=$(uuidgen)
export TF_VAR_user_data_path=$(pwd)/modules/scripts/user_data.sh
# Define Terraform module directory
TERRAFORM_MODULES_DIR=$(pwd)/modules/terraform/$CLOUD

# Provision resources
pushd $TERRAFORM_MODULES_DIR
terraform init
terraform plan
terraform apply --auto-approve
popd
