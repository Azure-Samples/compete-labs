#!/bin/bash

source scripts/utils.sh

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

set_aws_variables() {
  REGION=${3:-us-west-2}
  export TF_VAR_region=$REGION
  active_reservations=$(aws ec2 describe-capacity-reservations \
    --region $REGION \
    --filters Name=state,Values=active \
    --query "CapacityReservations[*].{ReservationId:CapacityReservationId, AvailableCount:AvailableInstanceCount}" \
    --output json)

  capacity_reservation_id=""
  # Read the active reservations into an array
  IFS=$'\n' readarray -t reservations <<< "$(echo "$active_reservations" | jq -c '.[]')"

  # Loop over each reservation in the array
  for reservation in "${reservations[@]}"; do
    reservation_id=$(echo "$reservation" | jq -r '.ReservationId')
    available_count=$(echo "$reservation" | jq -r '.AvailableCount')
        
    if [ -n "$available_count" ] && [ "$available_count" -gt 0 ]; then
      capacity_reservation_id=$reservation_id
      break
    fi
  done

  if [ -z "$capacity_reservation_id" ]; then
    echo -e "${RED}Error: No active capacity reservations with available instances found in $REGION${NC}"
  fi

  export TF_VAR_capacity_reservation_id=$capacity_reservation_id
  export TF_VAR_zone_suffix="a"
}

provision_resources() {
  local error_file="/tmp/${TF_VAR_run_id}-provision-error.txt"
  pushd modules/terraform/$CLOUD
  terraform init
  echo "Provisioning resources in $CLOUD..."
  start_time=$(date +%s)
  terraform apply -auto-approve 2> $error_file
  local exit_code=$?
  end_time=$(date +%s)
  export PROVISION_LATENCY=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}Resources are provisioned successfully!${NC}"
    export PROVISION_STATUS="Success"
  else
    echo -e "${RED}Error: Failed to provision resources: $(cat $error_file)${NC}"
    export PROVISION_STATUS="Failure"
    export PROVISION_ERROR=$(cat $error_file)
  fi
  echo -e "${YELLOW}Provision status: $PROVISION_STATUS, Provision latency: $PROVISION_LATENCY seconds${NC}"
  popd
}

cleanup_resources() {
  local error_file="/tmp/${TF_VAR_run_id}-cleanup-error.txt"
  pushd modules/terraform/$CLOUD
  echo "Cleaning up resources in $CLOUD..."
  start_time=$(date +%s)
  terraform destroy -auto-approve 2> $error_file
  local exit_code=$?
  end_time=$(date +%s)
  export CLEANUP_LATENCY=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}Resources are cleaned up successfully!${NC}"
    export CLEANUP_STATUS="Success"
  else
    echo -e "${RED}Error: Failed to clean up resources: $(cat $error_file)${NC}"
    export CLEANUP_STATUS="Failure"
    export CLEANUP_ERROR=$(cat $error_file)
  fi
  rm -f terraform.tfstate*
  echo -e "${YELLOW}Cleanup status: $CLEANUP_STATUS, Cleanup latency: $CLEANUP_LATENCY seconds${NC}"
  popd

  rm -f private_key.pem*
}

set_azure_variables() {
  REGION=${3:-eastus2}  
  export TF_VAR_region=$REGION
}

set_${CLOUD}_variables $3

case $ACTION in
  provision)
    confirm "provision_resources"
    provision_resources
    ;;
  cleanup)
    confirm "cleanup_resources"
    cleanup_resources
    ;;
  *)
    echo "Invalid action: $ACTION"
    exit 1
    ;;
esac