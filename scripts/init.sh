#!/bin/bash

source scripts/utils.sh

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${RED}This script must be sourced. Run it with: source $0${NC}"
    exit 0
fi

if ! command -v az &> /dev/null
then
    echo "Azure CLI not found. Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
    echo "Azure CLI is already installed."
fi

az --version

if ! command -v aws &> /dev/null
then
    echo "AWS CLI not found. Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install -i $HOME/.aws-cli -b $HOME/.local/bin --update
    rm awscliv2.zip
    rm -rf aws
    export PATH=$PATH:$HOME/.local/bin
else
    echo "AWS CLI is already installed."
fi

aws --version

if ! command -v terraform &> /dev/null
then
    echo "Terraform not found. Installing Terraform..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update && sudo apt-get install terraform
else
    echo "Terraform is already installed."
fi

terraform --version

echo "Please login to Microsoft Account..."
az login --use-device-code

# Unset variables with *_STATUS, *_LATENCY, *_ERROR pattern
for var in $(compgen -v | grep -E '_STATUS$|_LATENCY$|_ERROR$'); do
  unset $var
done

ssh_key_path=$(pwd)/private_key.pem
TF_VAR_ssh_public_key="${ssh_key_path}.pub"
export TF_VAR_ssh_public_key
export SSH_KEY_PATH=$ssh_key_path
if [ -f $SSH_KEY_PATH ]; then
    echo "SSH key already exists."
else
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f $SSH_KEY_PATH -N ""
fi
export TF_VAR_user_data_path=$(pwd)/modules/user_data/user_data.sh

echo "Fetching secrets from Azure Key Vault..."
azure_subscription_id=$(az keyvault secret show --vault-name aks-compete-labs --name azure-subscription --query value -o tsv)
aws_username=$(az keyvault secret show --vault-name aks-compete-labs --name aws-username --query value -o tsv)
aws_password=$(az keyvault secret show --vault-name aks-compete-labs --name aws-password --query value -o tsv)
aws_access_key_id=$(az keyvault secret show --vault-name aks-compete-labs --name aws-access-key-id --query value -o tsv)
aws_secret_access_key=$(az keyvault secret show --vault-name aks-compete-labs --name aws-secret-access-key --query value -o tsv)
HUGGING_FACE_TOKEN=$(az keyvault secret show --vault-name aks-compete-labs --name hugging-face-token --query value -o tsv)
VLLM_API_KEY=$(az keyvault secret show --vault-name aks-compete-labs --name vllm-api-key --query value -o tsv)

export HUGGING_FACE_TOKEN
export VLLM_API_KEY
export ARM_SUBSCRIPTION_ID=$azure_subscription_id

az account set --subscription $azure_subscription_id

echo "Logging in to AWS..."
aws configure set aws_access_key_id $aws_access_key_id
aws configure set aws_secret_access_key $aws_secret_access_key
aws configure set region us-west-2
aws sts get-caller-identity &> /dev/null

USER_EMAIL=$(jq -r '.subscriptions[0].user.name' ~/.azure/azureProfile.json)
export USER_EMAIL
USER_ALIAS=$(echo $USER_EMAIL | cut -d'@' -f1)
export TF_VAR_owner=$USER_ALIAS
echo "Welcome $USER_ALIAS to Compete Lab!"