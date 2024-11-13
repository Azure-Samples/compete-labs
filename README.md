# Compete Codelabs

This project simulates a startup CEO trying to build a cloud-native intelligent app based on an open-source large language model. It aims to quickly test and compare different cloud providers to find the best performance and prices.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=Azure-Samples/compete-labs)

## Getting Started

### Setup

```bash
source init.sh
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

### Provision resources
```bash
source scripts/resources.sh provision $CLOUD $REGION
```

## Measure Performance

```bash
source scripts/run.sh $CLOUD
```

## Cleanup Resources
```bash
source scripts/resources.sh destroy $CLOUD $REGION
```

Measure latency of provision resources

## Upload Results

Calculate cost based on the hourly rate of VM SKU and total time spent, add add it to results.json using jq.

```bash
source scripts/publish.sh $CLOUD
```
