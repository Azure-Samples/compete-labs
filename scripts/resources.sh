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
    echo "Resources are provisioned successfully!"
    export PROVISION_STATUS="Success"
  else
    echo "Error: Failed to provision resources!"
    export PROVISION_STATUS="Failure"
    export PROVISION_ERROR=$(cat $error_file)
  fi
  echo "Provision status: $PROVISION_STATUS, Provision latency: $PROVISION_LATENCY seconds"
  popd
}

destroy_resources() {
  local error_file="/tmp/${TF_VAR_run_id}-destroy-error.txt"
  pushd modules/terraform/$CLOUD
  echo "Destroying resources in $CLOUD..."
  start_time=$(date +%s)
  terraform destroy -auto-approve 2> $error_file
  local exit_code=$?
  end_time=$(date +%s)
  export DESTROY_LATENCY=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    echo "Resources are destroyed successfully!"
    export DESTROY_STATUS="Success"
  else
    echo "Error: Failed to destroy resources!"
    export DESTROY_STATUS="Failure"
    export DESTROY_ERROR=$(cat $error_file)
  fi
  echo "Destroy status: $DESTROY_STATUS, Destroy latency: $DESTROY_LATENCY seconds"

  popd
  rm -f private_key.pem*
}

set_azure_variables() {
  REGION=${3:-eastus2}
  export TF_VAR_region=$REGION
}

set_common_variables() {
  export TF_VAR_user_data_path=$(pwd)/modules/scripts/user_data.sh
}

set_ssh_path
set_common_variables
set_${CLOUD}_variables $3

case $ACTION in
  provision)
    generate_ssh_key
    provision_resources
    ;;
  destroy)
    destroy_resources
    ;;
  *)
    ;;
esac
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
    echo "Resources are provisioned successfully!"
    export PROVISION_STATUS="Success"
  else
    echo "Error: Failed to provision resources: $(cat $error_file)"
    export PROVISION_STATUS="Failure"
    export PROVISION_ERROR=$(cat $error_file)
  fi
  echo "Provision status: $PROVISION_STATUS, Provision latency: $PROVISION_LATENCY seconds"
  popd
}

destroy_resources() {
  local error_file="/tmp/${TF_VAR_run_id}-destroy-error.txt"
  pushd modules/terraform/$CLOUD
  echo "Destroying resources in $CLOUD..."
  start_time=$(date +%s)
  terraform destroy -auto-approve 2> $error_file
  local exit_code=$?
  end_time=$(date +%s)
  export DESTROY_LATENCY=$((end_time - start_time))

  if [[ $exit_code -eq 0 ]]; then
    echo "Resources are destroyed successfully!"
    export DESTROY_STATUS="Success"
  else
    echo "Error: Failed to destroy resources: $(cat $error_file)"
    export DESTROY_STATUS="Failure"
    export DESTROY_ERROR=$(cat $error_file)
  fi
  echo "Destroy status: $DESTROY_STATUS, Destroy latency: $DESTROY_LATENCY seconds"

  popd
  rm -f private_key.pem*
}

set_azure_variables() {
  REGION=${3:-eastus2}
  export TF_VAR_region=$REGION
}

set_common_variables() {
  export TF_VAR_user_data_path=$(pwd)/modules/user_data/user_data.sh
}

set_ssh_path
set_common_variables
set_${CLOUD}_variables $3

case $ACTION in
  provision)
    generate_ssh_key
    provision_resources
    ;;
  destroy)
    destroy_resources
    ;;
  *)
    ;;
esac
