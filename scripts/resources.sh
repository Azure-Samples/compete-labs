#!/bin/bash

source scripts/utils.sh
source scripts/azure.sh

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${RED}This script must be sourced. Run it with: source $0${NC}"
    exit 0
fi

# Check if action and cloud are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <action> <cloud> [region]"
  echo "Action options: provision, cleanup"
  echo "Cloud options: aws, azure"
  echo "Region (optional, defaults to 'us-west-2' for AWS and 'eastus' for Azure)"
fi

ACTION=$1
CLOUD=$2

set_aws_variables() {
  REGION=${3:-us-west-2}
  export TF_VAR_region=$REGION
  if [ -z "$TF_VAR_capacity_reservation_id" ]; then
    capacity_reservation_id=$(aws ec2 describe-capacity-reservations \
      --region $REGION \
      --filters Name=state,Values=active \
      --query "CapacityReservations[*].{ReservationId:CapacityReservationId, AvailableCount:AvailableInstanceCount}" \
      --output json | jq -r 'map(select(.AvailableCount > 0)) | .[0].ReservationId')

    if [ -z "$capacity_reservation_id" ]; then
      echo -e "${RED}Error: No active capacity reservations with available instances found in $REGION${NC}"
    fi
  fi

  export TF_VAR_capacity_reservation_id=$capacity_reservation_id
  export TF_VAR_zone_suffix="a"
}

provision_resources() {
  local error_file="/tmp/${TF_VAR_run_id}/${CLOUD}/provision-error.txt"
  mkdir -p "$(dirname "$error_file")"
  pushd modules/terraform/$CLOUD
  echo "Provisioning resources in $CLOUD..."
  if [ "$CLOUD" == "aws" ]; then
    terraform init
    start_time=$(date +%s)
    terraform apply -auto-approve 2> $error_file
  elif [ "$CLOUD" == "azure" ]; then
    start_time=$(date +%s)
    create_resources $TF_VAR_run_id $TF_VAR_owner $REGION $TF_VAR_ssh_public_key $TF_VAR_user_data_path 2> $error_file
  fi
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
  publish_results "provision" $CLOUD
  popd
}

cleanup_resources() {
  local error_file="/tmp/${TF_VAR_run_id}/${CLOUD}/cleanup-error.txt"
  mkdir -p "$(dirname "$error_file")"
  pushd modules/terraform/$CLOUD
  echo "Cleaning up resources in $CLOUD..."

  # check for terraform state files
  if [ ! -f terraform.tfstate ]; then
    echo -e "${YELLOW}Terraform state files not found. Cleanup using cli${NC}"
    cleanup_resources_using_cli

  else
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
  fi
  publish_results "cleanup" $CLOUD
  popd
}

cleanup_resources_using_cli() {
  if [ "$CLOUD" == "aws" ]; then
    local instance_id=$(aws ec2 describe-instances \
      --region $REGION \
      --filters Name=tag:owner,Values=$TF_VAR_owner \
      --query "Reservations[*].Instances[*].InstanceId" \
      --output text)

    if [ -n "$instance_id" ]; then
      start_time=$(date +%s)
      aws ec2 terminate-instances --region $REGION --instance-ids $instance_id
      echo "Waiting for instance to terminate. It may take 10-15 minutes to terminate the instance..."
      aws ec2 wait instance-terminated --region $REGION --instance-ids $instance_id

      # List and delete security groups
      security_group_ids=$(aws ec2 describe-security-groups --filters Name=tag:owner,Values=$TF_VAR_owner --query "SecurityGroups[?GroupName != 'default'].[GroupId]" --output text)
      for security_group_id in $security_group_ids; do
        ip_permission_ingress=$(aws ec2 describe-security-groups --group-ids $security_group_id \
          --query "SecurityGroups[0].IpPermissions" --output json)
        if [ "$ip_permission_ingress" != "[]" ]; then
          echo "Deleting Security Group Ingress Rules for Security Group: $security_group_id"
          if ! aws ec2 revoke-security-group-ingress \
            --cli-input-json "{\"GroupId\": \"$security_group_id\", \"IpPermissions\": $ip_permission_ingress}"; then
            echo "Failed to revoke ingress permissions for Security Group: $security_group_id"
          fi
        fi

        ip_permission_egress=$(aws ec2 describe-security-groups --group-ids $security_group_id \
          --query "SecurityGroups[0].IpPermissionsEgress" --output json)
        if [ "$ip_permission_egress" != "[]" ]; then
          echo "Deleting Security Group Egress Rules for Security Group: $security_group_id"
          if ! aws ec2 revoke-security-group-egress \
            --cli-input-json "{\"GroupId\": \"$security_group_id\", \"IpPermissions\": $ip_permission_egress}"; then
            echo "Failed to revoke egress permissions for Security Group: $security_group_id"
          fi
        fi

        echo "Deleting Security Group: $security_group_id"
        if ! aws ec2 delete-security-group --group-id $security_group_id; then
          echo "Failed to delete Security Group: $security_group_id"
        fi
      done

      # List and delete subnets
      subnet_ids=$(aws ec2 describe-subnets --filters Name=tag:owner,Values=$TF_VAR_owner --query "Subnets[*].[SubnetId]" --output text)
      for subnet_id in $subnet_ids; do
        echo "Deleting Subnet: $subnet_id"

        # Check for ENIs attached to the subnet and delete them
        eni_ids=$(aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=$subnet_id" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        for eni_id in $eni_ids; do
          echo "Deleting ENI: $eni_id"
          if ! aws ec2 delete-network-interface --network-interface-id $eni_id; then
            echo "Failed to delete ENI: $eni_id"
          fi
        done

        # Delete the subnet after deleting attached ENIs
        if ! aws ec2 delete-subnet --subnet-id $subnet_id; then
          echo "Failed to delete Subnet: $subnet_id"
        fi
      done
      route_table_id=$(aws ec2 describe-route-tables --filters Name=tag:owner,Values=$TF_VAR_owner --query "RouteTables[*].[RouteTableId]" --output text)
      if [ -n "$route_table_id" ]; then
        echo "Deleting Route Table: $route_table_id"
        aws ec2 delete-route-table --route-table-id $route_table_id
      fi
      internet_gateway_id=$(aws ec2 describe-internet-gateways --filters Name=tag:owner,Values=$TF_VAR_owner --query "InternetGateways[*].[InternetGatewayId]" --output text)
      if [ -n "$internet_gateway_id" ]; then
        echo "Detaching and Deleting Internet Gateway: $internet_gateway_id"
        aws ec2 detach-internet-gateway --internet-gateway-id $internet_gateway_id --vpc-id $vpc_id
        aws ec2 delete-internet-gateway --internet-gateway-id $internet_gateway_id
      fi
      vpc_id=$(aws ec2 describe-vpcs --filters Name=tag:owner,Values=$TF_VAR_owner --query "Vpcs[*].[VpcId]" --output text)
      if [ -n "$vpc_id" ]; then
        echo "Deleting VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id $vpc_id
      fi
      end_time=$(date +%s)
      export CLEANUP_LATENCY=$((end_time - start_time))
      export CLEANUP_STATUS="Success"
    fi
  elif [ "$CLOUD" == "azure" ]; then
    echo "Deleting resource group: compete-labs-$TF_VAR_owner"
    start_time=$(date +%s)
    az group delete --name "compete-labs-$TF_VAR_owner" --yes
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
  fi
  publish_results "cleanup" $CLOUD
}


check_for_existing_resources() {
  local cloud=$1
  local region=$2

  resources_exist=false

  if [ "$cloud" == "aws" ]; then
    local instance_id=$(aws ec2 describe-instances \
      --region $region \
      --filters Name=tag:owner,Values=$TF_VAR_owner \
      --query "Reservations[*].Instances[*].InstanceId" \
      --output text)

    if [ -n "$instance_id" ]; then
      echo -e "${YELLOW}Warning: VM already exist with owner $TF_VAR_owner in $region${NC}"
      resources_exist=true
      # Get reservation id from the vm tags
      local reservation_id=$(aws ec2 describe-instances \
        --region $region \
        --instance-ids $instance_id \
        --query "Reservations[*].Instances[*].CapacityReservationId" \
        --output json | jq -r '.[0][0]')
      export TF_VAR_capacity_reservation_id=$reservation_id
      run_id=$(aws ec2 describe-instances \
        --region $region \
        --instance-ids $instance_id \
        --query "Reservations[*].Instances[*].Tags[?Key=='run_id'].Value" \
        --output json | jq -r '.[0][0][0]')
      export TF_VAR_run_id=$run_id
    fi
  elif [ "$cloud" == "azure" ]; then
    # Get VM under the resource group with owner tag
    resource_group_name=$(az resource list \
      --tag owner=$TF_VAR_owner \
      --query "[?type=='Microsoft.Compute/virtualMachines'].resourceGroup" \
      --output tsv)

    if [ -n "$resource_group_name" ]; then
      echo -e "${YELLOW}Warning: VM already exist with owner $TF_VAR_owner ${NC}"
      resources_exist=true
      run_id=$(az group show --name  $resource_group_name --query "tags.run_id" -o tsv)
      export TF_VAR_run_id=$run_id      
    fi
  fi
}

set_azure_variables() {
  REGION=${3:-eastus2}
  export TF_VAR_region=$REGION
}

case $ACTION in
  provision)
    set_${CLOUD}_variables $3
    check_for_existing_resources $CLOUD $REGION
    if [ "$resources_exist" == true ]; then
      echo -e "${YELLOW}Please proceed with running tests${NC}"
    else
      RUN_ID=$(uuidgen)
      export TF_VAR_run_id=$RUN_ID
      confirm "provision_resources"
      provision_resources
    fi
    ;;
  cleanup)
    confirm "cleanup_resources"
    cleanup_resources
    ;;
  *)
    echo "Invalid action: $ACTION"
    ;;
esac