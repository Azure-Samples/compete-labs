if ! command -v az &> /dev/null
then
    echo "Azure CLI not found. Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
    echo "Azure CLI is already installed."
fi

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

if ! command -v terraform &> /dev/null
then
    echo "Terraform not found. Installing Terraform..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update && sudo apt-get install terraform
else
    echo "Terraform is already installed."
fi

echo "Please login to Microsoft Account"
if ! az account show &> /dev/null
then
    echo "Please login to Microsoft Account"
    az login --use-device-code
else
    echo "Already logged in to Azure."
fi

alias=$(jq -r '.subscriptions[0].user.name' ~/.azure/azureProfile.json)
echo "Welcome $alias to Compete Lab!"