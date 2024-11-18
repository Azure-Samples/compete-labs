#!/bin/bash

source scripts/utils.sh

publish_results_to_storage_account() {    
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
