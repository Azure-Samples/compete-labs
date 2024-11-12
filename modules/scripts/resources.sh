#!/bin/bash

# Check if action and cloud are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <action> <cloud> [region]"
  echo "Action options: provision, cleanup"
  echo "Cloud options: aws, azure"
  echo "Region (optional, defaults to 'us-west-2' for AWS and 'eastus' for Azure)"
  exit 1
fi

ACTION=$1
CLOUD=$2

set_ssh_path() {
  ssh_key_path=$(pwd)/private_key.pem
  TF_VAR_ssh_public_key="${ssh_key_path}.pub"
  export TF_VAR_ssh_public_key
  export SSH_KEY_PATH=$ssh_key_path
}

generate_ssh_key() {
  ssh-keygen -t rsa -b 2048 -f $ssh_key_path -N ""
}

set_aws_variables() {
  REGION=${3:-us-west-2}
  export TF_VAR_region=$REGION
  capacity_reservation_id=$(aws ec2 describe-capacity-reservations \
    --region $REGION \
    --filters Name=state,Values=active \
    --query "CapacityReservations[0].[CapacityReservationId]" \
    --output text)
  if [ -z "$capacity_reservation_id" ]; then
    echo "No active capacity reservation found in $REGION"
    exit 1
  fi
  export TF_VAR_capacity_reservation_id=$capacity_reservation_id
  export TF_VAR_zone_suffix="a"
}

set_azure_variables() {
  REGION=${3:-eastus2}
  export TF_VAR_region=$REGION
}

set_common_variables() {
  export TF_VAR_owner=$(whoami)
  export TF_VAR_user_data_path=$(pwd)/modules/scripts/user_data.sh
  TERRAFORM_MODULES_DIR=modules/terraform/$CLOUD
}

set_ssh_path
set_common_variables
set_${CLOUD}_variables $3

case $ACTION in
  provision)
    generate_ssh_key
    ;;
  *)
    ;;
esac
