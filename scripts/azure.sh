#!/bin/bash

create_resources() {
    local run_id=$1
    local owner=$2
    local location=$3
    local ssh_public_key_path=$4
    local user_data_path=$5

    local resource_group="compete-labs-${owner}"
    local tags="Name=compete-labs deletion_due_time=$(date -d '8 hours' -u +%Y-%m-%dT%H:%M:%SZ) owner=${owner} run_id=${run_id}"

    Create Resource Group
    az group create --name $resource_group --location $location --tags $tags

    # Create Public IP
    az network public-ip create --resource-group $resource_group \
        --name chatbot-server-pip --allocation-method Static --sku Standard --tags $tags

    # Create Virtual Network
    az network vnet create --resource-group $resource_group \
        --name chatbot-vnet --address-prefix 10.0.0.0/16 --tags $tags

    # Create Subnet
    az network vnet subnet create --resource-group $resource_group \
        --vnet-name chatbot-vnet --name chatbot-subnet --address-prefix 10.0.1.0/24

    # Create Network Security Group
    az network nsg create --resource-group $resource_group \
        --name chatbot-nsg --tags $tags

    # Create Network Security Rules
    az network nsg rule create --resource-group $resource_group \
        --nsg-name chatbot-nsg --name SSH --priority 1001 \
        --direction Inbound --access Allow --protocol Tcp --source-port-range '*' \
        --destination-port-range 2222 --source-address-prefix '*' --destination-address-prefix '*'
    az network nsg rule create --resource-group $resource_group \
        --nsg-name chatbot-nsg --name HTTP --priority 1002 \
        --direction Inbound --access Allow --protocol Tcp --source-port-range '*' \
        --destination-port-range 80 --source-address-prefix '*' --destination-address-prefix '*'
    az network nsg rule create --resource-group $resource_group \
        --nsg-name chatbot-nsg --name HTTPS --priority 1003 \
        --direction Inbound --access Allow --protocol Tcp --source-port-range '*' \
        --destination-port-range 443 --source-address-prefix '*' --destination-address-prefix '*'

    # Associate NSG with Subnet
    az network vnet subnet update --resource-group $resource_group \
        --vnet-name chatbot-vnet --name chatbot-subnet --network-security-group chatbot-nsg

    # Create Network Interface
    az network nic create --resource-group $resource_group \
        --name chatbot-server-nic --vnet-name chatbot-vnet --subnet chatbot-subnet \
        --public-ip-address chatbot-server-pip --accelerated-networking --tags $tags

    # Create Linux Virtual Machine
    az vm create --resource-group $resource_group \
        --name chatbot-server --size Standard_NC96ads_A100_v4 \
        --nics chatbot-server-nic --zone 2 \
        --os-disk-caching ReadWrite --storage-sku Premium_LRS --os-disk-size-gb 256 \
        --image microsoft-dsvm:ubuntu-hpc:2204:latest \
        --admin-username ubuntu --ssh-key-value @${ssh_public_key_path} --tags $tags

    # Add Custom Script Extension to VM
    setting=$(jq -n -c --arg script "$(base64 $user_data_path)" '{script: $script}')
    az vm extension set --resource-group $resource_group \
        --vm-name chatbot-server \
        --name CustomScript --publisher Microsoft.Azure.Extensions --version 2.0 \
        --protected-settings "$setting"
}