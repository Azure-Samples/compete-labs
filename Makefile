SHELL := /bin/bash

CLOUD := azure
REGION := eastus2
SCRIPTS_DIR := scripts

.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "make all CLOUD=azure REGION=eastus2"
	@echo "make all CLOUD=aws REGION=us-west-2"

all: 
	@echo "Creating resources in $(CLOUD) region $(REGION)"
	source init.sh && \
	$(SCRIPTS_DIR)/resources.sh provision $(CLOUD) $(REGION) && \
	$(SCRIPTS_DIR)/run.sh $(CLOUD) && \
	$(SCRIPTS_DIR)/resources.sh destroy $(CLOUD) $(REGION) && \
	$(SCRIPTS_DIR)/publish.sh $(CLOUD)

