# Compete Labs

This codelab simulates scenarios where a startup CEO is trying to build a cloud-native intelligent app based on an open-source large language model. In particular, they want to quickly test and compare different cloud providers to find the best price performance.

In this codelab, you will follow a step-by-step guide to experiment with state-of-the-art hardware like [Nvidia A100 GPU chips](https://www.nvidia.com/en-us/data-center/a100/), large language model like [Meta Llama 3.1](https://ai.meta.com/blog/meta-llama-3-1/), and software like [vLLM](https://github.com/vllm-project/vllm). You'll leverage cloud-native technologies like [Terraform](https://www.terraform.io/), [Docker](https://www.docker.com/), and [Linux Bash](https://www.gnu.org/software/bash/manual/bash.html) on major cloud providers such as [Azure](https://azure.microsoft.com/) and [AWS](https://aws.amazon.com/).

# User Guide

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=Azure-Samples/compete-labs)

## Setup Tests
```bash
source scripts/init.sh
```

### Set AWS Cloud Variable
```bash
export CLOUD=aws
export REGION=us-west-2
```
### Set AZURE Cloud Variable
```bash
export CLOUD=azure
export REGION=eastus2
```

## Provision Resources
```bash
source scripts/resources.sh provision $CLOUD $REGION
```

## Running Tests

### Deploying the server
```bash
source scripts/server.sh deploy $CLOUD
```

### Starting the server
```bash
source scripts/server.sh start $CLOUD
```

### Testing the server
```bash
source scripts/server.sh test $CLOUD
```

## Cleanup Resources
```bash
source scripts/resources.sh cleanup $CLOUD $REGION
```

## Upload Results
```bash
source scripts/publish.sh $CLOUD
```
