#!/bin/bash

# Check if cloud is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <cloud>"
  echo "Cloud options: aws, azure"
  exit 1
fi

# Set the cloud environment based on input
CLOUD=$1
echo "Cleaning up resources for cloud: $CLOUD"

# Set Cloud-specific variables
if [ "$CLOUD" == "aws" ]; then
  REGION=${2:-us-west-2}
  export TF_VAR_region="$REGION"
  TF_VAR_capacity_reservation_id=$(aws ec2 describe-capacity-reservations \
    --region $REGION \
    --filters Name=state,Values=active \
    --query "CapacityReservations[0].[CapacityReservationId]" \
    --output text)
  export TF_VAR_capacity_reservation_id
  export TF_VAR_zone_suffix="a"
elif [ "$CLOUD" == "azure" ]; then
  REGION=${2:-eastus2}
  export TF_VAR_region=$REGION
else
  echo "Invalid cloud: $CLOUD. Please use 'aws' or 'azure'."
  exit 1
fi

# Define Terraform module directory
TERRAFORM_MODULES_DIR=modules/terraform/$CLOUD

# Set general variables
export TF_VAR_owner=$(whoami)
export TF_VAR_run_id=$(uuidgen)
ssh_key_path=$(pwd)/private_key.pem
export TF_VAR_ssh_public_key="${ssh_key_path}.pub"
export TF_VAR_user_data_path=$(pwd)/modules/scripts/user_data.sh
# Clean up resources
pushd $TERRAFORM_MODULES_DIR
terraform init
terraform destroy --auto-approve
popd

# Remove SSH key pair
rm -f private_key.pem private_key.pem.pub
