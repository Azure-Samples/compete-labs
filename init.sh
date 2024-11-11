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
    sudo ./aws/install
    rm awscliv2.zip
    rm -rf aws
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

if ! az account show &> /dev/null
then
    echo "Please login to Microsoft Account"
    az login --use-device-code
else
    echo "Already logged in to Azure."
fi

echo "Fetching secrets from Azure Key Vault..."
aws_username=$(az keyvault secret show --vault-name aks-compete-labs --name aws-username --query value -o tsv)
aws_password=$(az keyvault secret show --vault-name aks-compete-labs --name aws-password --query value -o tsv)
HUGGING_FACE_TOKEN=$(az keyvault secret show --vault-name aks-compete-labs --name hugging-face-token --query value -o tsv)
VLLM_API_KEY=$(az keyvault secret show --vault-name aks-compete-labs --name vllm-api-key --query value -o tsv)

export HUGGING_FACE_TOKEN
export VLLM_API_KEY

echo "Logging in to AWS..."
aws configure set aws_access_key_id $aws_username
aws configure set aws_secret_access_key $aws_password
aws sts get-caller-identity &> /dev/null

USER_ALIAS=$(jq -r '.subscriptions[0].user.name' ~/.azure/azureProfile.json)
export USER_ALIAS
echo "Welcome $USER_ALIAS to Compete Lab!"