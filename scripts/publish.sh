#!/bin/bash

source scripts/utils.sh

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${RED}This script must be sourced. Run it with: source $0${NC}"
    exit 0
fi

PROVIDER=$1

publish_results_to_storage_account() {
  local result_file="/tmp/${TF_VAR_run_id}-${PROVIDER}-result.json"
  local storage_account="akstelescope"
  local container_name="compete-labs"

  echo "Uploading the result file $result_file to the cloud storage..."
  az storage blob upload --account-name $storage_account --auth-mode login --overwrite \
      --container-name $container_name --file $result_file --name "${TF_VAR_run_id}-${PROVIDER}.json"

  echo -e "${GREEN}Congratulations $USER_ALIAS on completing the $PROVIDER section of Compete Lab!"
}

# Main
confirm "publish_results_to_storage_account"
publish_results_to_storage_account
