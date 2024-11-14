# Compete Labs

This codelab simulates scenarios where a startup CEO is trying to build a cloud-native intelligent app based on an open-source large language model. In particular, they want to quickly test and compare different cloud providers to find the best price performance.

In this codelab, you will follow a step-by-step guide to experiment with state-of-the-art hardware like [Nvidia A100 GPU chips](https://www.nvidia.com/en-us/data-center/a100/), large language model like [Meta Llama 3.1](https://ai.meta.com/blog/meta-llama-3-1/), and software like [vLLM](https://github.com/vllm-project/vllm). You'll leverage cloud-native technologies like [Terraform](https://www.terraform.io/), [Docker](https://www.docker.com/), and [Linux Bash](https://www.gnu.org/software/bash/manual/bash.html) on major cloud providers such as [Azure](https://azure.microsoft.com/) and [AWS](https://aws.amazon.com/).

# User Guide

[![Open in Azure Cloud Shell](https://img.shields.io/badge/Azure%20Cloud%20Shell-Open-blue?logo=microsoft-azure)](https://shell.azure.com/bash?command=git%20clone%20YOUR_REPO_URL%3B%20cd%20YOUR_REPO_NAME)


## Setup Tests
Once the cloud shell is ready, clone the repository and enter the directory:
```bash
git clone https://github.com/Azure-Samples/compete-labs
cd compete-labs
```

Install dependencies, authenticate, and initialize environments by running the commands below:
```bash
source scripts/init.sh
```

### For Azure
```bash
export CLOUD=azure
export REGION=eastus2
```

### For AWS
```bash
export CLOUD=aws
export REGION=us-west-2
```


## Provision Resources
Provision infrastructure resources like GPU Virtual Machine:
```bash
source scripts/resources.sh provision $CLOUD $REGION
```

## Running Tests

### Deploying the server
Deploy the LLM-backed inferencing server using Docker:
```bash
source scripts/server.sh deploy $CLOUD
```

### Starting the server
Download the Llama 3 8B model from Hugging Face, load it into the GPUs, and start the HTTP server:
```bash
source scripts/server.sh start $CLOUD
```

### Testing the server
Send some prompt requests to the HTTP server to test chat completion endpoint:
```bash
source scripts/server.sh test $CLOUD
```

## Cleanup Resources
Cleanup infrastructure resources like GPU Virtual Machine:
```bash
source scripts/resources.sh cleanup $CLOUD $REGION
```

## Publish Results
Collect and upload test results to Azure Data Explorer
```bash
source scripts/publish.sh $CLOUD
```
Check out aggregated and visualized test results on the [dashboard](https://dataexplorer.azure.com/dashboards/8a3e24d9-2907-40c3-a1ac-310ef4aeb608)