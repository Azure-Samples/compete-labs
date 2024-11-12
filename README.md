# Compete Codelabs

This project simulates a startup CEO trying to build a cloud-native intelligent app based on an open-source large language model. It aims to quickly test and compare different cloud providers to find the best performance and prices.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?repo=Azure-Samples/compete-labs)

## Getting Started

### Setup

```bash
source init.sh
```


### Make Commands
```bash
  ```bash
  make create-resources CLOUD=azure REGION=eastus2
  make create-resources CLOUD=aws REGION=us-west-2
  make validate-resources CLOUD=azure REGION=eastus2
  make validate-resources CLOUD=aws REGION=us-west-2
  make cleanup-resources CLOUD=azure REGION=eastus2
  make cleanup-resources CLOUD=aws REGION=us-west-2
  make all CLOUD=azure REGION=eastus2
  ```
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
