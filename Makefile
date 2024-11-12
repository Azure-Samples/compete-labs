SHELL := /bin/bash

CLOUD := azure
REGION := eastus2
SCRIPTS_DIR := modules/scripts
TERRAFORM_MODULES_DIR := modules/terraform/$(CLOUD)

.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "make create-resources CLOUD=azure REGION=eastus2"
	@echo "make create-resources CLOUD=aws REGION=us-west-2"
	@echo "make validate-resources CLOUD=azure REGION=eastus2"
	@echo "make validate-resources CLOUD=aws REGION=us-west-2"
	@echo "make cleanup-resources CLOUD=azure REGION=eastus2"
	@echo "make cleanup-resources CLOUD=aws REGION=us-west-2"
	@echo "make all CLOUD=azure REGION=eastus2"

all: create-resources validate-resources run-tests cleanup-resources

create-resources:
	@echo "Creating resources in $(CLOUD) cloud provider in $(REGION) region"
	source $(SCRIPTS_DIR)/resources.sh provision $(CLOUD) && \
	pushd $(TERRAFORM_MODULES_DIR) && \
	terraform init && \
	terraform apply -auto-approve

validate-resources:
	@echo "Validating resources in $(CLOUD) cloud provider in $(REGION) region"
	# Todo: Add validation logic

run-tests:
	@echo "Running tests in $(CLOUD) cloud provider in $(REGION) region"
	source $(SCRIPTS_DIR)/resources.sh test $(CLOUD) && \
	source $(SCRIPTS_DIR)/run.sh $(CLOUD)

cleanup-resources:
	@echo "Cleaning up resources in $(CLOUD) cloud provider in $(REGION) region"
	source $(SCRIPTS_DIR)/resources.sh cleanup $(CLOUD) && \
	pushd $(TERRAFORM_MODULES_DIR) && \
	terraform destroy -auto-approve && \
	popd && \
	rm -f private_key.pem private_key.pem.pub

