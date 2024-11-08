# Run Azure Compete lab using Terraform

### Prerequisites
- Install [Terraform](https://www.terraform.io/downloads.html)
- Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- An Azure account

### Generate SSH public and private key using SSH Keygen
```bash
ssh_key_path=$(pwd)/private_key.pem
ssh-keygen -t rsa -b 2048 -f $ssh_key_path -N ""
TF_VAR_ssh_public_key="${ssh_key_path}.pub"
export TF_VAR_ssh_public_key
```

### Set Variables
```bash
CLOUD=aws
TERRAFORM_MODULES_DIR=modules/terraform/$CLOUD
```

### Provision resources
```bash
pushd $TERRAFORM_MODULES_DIR
terraform init
terraform plan
terraform apply --auto-approve
```

### Destroy resources
```bash
terraform destroy --auto-approve
```