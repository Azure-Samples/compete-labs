#!/bin/bash

source scripts/utils.sh

PROVIDER=$1
AWS_HOURLY_COST=32.7726
AZURE_HOURLY_COST=14.69

publish_results() {    
    local storage_account="akstelescope"
    local container_name="compete-labs"

    echo "Uploading the result file $result_file to the cloud storage..."
    az storage blob upload --account-name $storage_account --auth-mode login --overwrite \
        --container-name $container_name --file $result_file --name "${TF_VAR_run_id}-${PROVIDER}.json"

    echo -e "${GREEN}Congratulations $USER_ALIAS on completing the $PROVIDER section of Compete Lab!"
}

# Main
confirm "publish_results"
publish_results
