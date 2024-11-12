# Compete Codelabs

This project simulates a startup CEO trying to build a cloud-native intelligent app based on an open-source large language model. It aims to quickly test and compare different cloud providers to find the best performance and prices.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=Azure-Samples/compete-labs)

## Getting Started

### Setup

```bash
source init.sh
```

### Generate SSH public and private key using SSH Keygen
```bash
ssh_key_path=$(pwd)/private_key.pem
TF_VAR_ssh_public_key="${ssh_key_path}.pub"
ssh-keygen -t rsa -b 2048 -f $ssh_key_path -N ""
export TF_VAR_ssh_public_key
export SSH_KEY_PATH=$ssh_key_path
```

### Set AWS Cloud Variable
```bash
CLOUD=aws
export TF_VAR_region=us-west-2
export TF_VAR_zone_suffix=a
export TF_VAR_capacity_reservation_id="cr-0819f1716eaf8a4a9"
```
### Set AZURE Cloud Variable
```bash
CLOUD=azure
export TF_VAR_region=eastus2
```

### Provision resources
```bash
export TF_VAR_owner=$(whoami)
export TF_VAR_run_id=$(uuidgen)
export TF_VAR_user_data_path=$(pwd)/modules/scripts/user_data.sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TERRAFORM_MODULES_DIR=modules/terraform/$CLOUD
pushd $TERRAFORM_MODULES_DIR
terraform init
terraform plan
terraform apply --auto-approve
```

## Measure Performance

```bash
source scripts/run.sh $CLOUD
```

## Cleanup Resources
```bash
make cleanup-resources CLOUD=azure REGION=eastus2
make cleanup-resources CLOUD=aws REGION=us-west-2
```

Measure latency of provision resources

## Upload Results

Calculate cost based on the hourly rate of VM SKU and total time spent, add add it to results.json using jq.

```bash
source scripts/publish.sh $CLOUD
```
