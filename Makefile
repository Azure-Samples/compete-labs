SHELL := /bin/bash

CLOUD := azure
REGION := eastus2
SCRIPTS_DIR := modules/scripts
TERRAFORM_MODULES_DIR := modules/terraform/$(CLOUD)

.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "make all CLOUD=azure REGION=eastus2"
  @echo "make all CLOUD=aws REGION=us-west-2"

all: 
  @echo "Creating resources in $(CLOUD) region $(REGION)"
  source 

