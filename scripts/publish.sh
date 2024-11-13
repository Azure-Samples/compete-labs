#!/bin/bash

source scripts/utils.sh

PROVIDER=$1

publish_results() {
    local result_file="/tmp/${TF_VAR_run_id}-result.json"
    local storage_account="akstelescope"
    local container_name="compete-labs"
    local cloud_info=$(jq -n \
        --arg provider "$PROVIDER" \
        --arg region "$TF_VAR_region" \
        '{provider: $provider, region: $region}')

    steps="provision validate deploy start test cleanup"
    for step in $steps; do
        status_var="${step^^}_STATUS"
        latency_var="${step^^}_LATENCY"
        error_var="${step^^}_ERROR"

        eval "step_info=\$(jq -n \
            --arg status \"\${!status_var}\" \
            --arg latency \"\${!latency_var}\" \
            --arg error \"\${!error_var}\" \
            '{status: \$status, latency: \$latency, error: \$error}')"
        echo "Processed step $step: $step_info"

        result=$(jq -n \
            --arg timestamp "$(date +%s)" \
            --arg run_id "$TF_VAR_run_id" \
            --arg owner "$USER_ALIAS" \
            --arg cloud_info "$cloud_info" \
            --arg step "$step" \
            --arg step_info "$step_info" \
            '{
                timestamp: $timestamp,
                run_id: $run_id,
                owner: $owner,
                cloud_info: $cloud_info,
                step: $step,
                result: $step_info
            }')
        echo $result >> $result_file
    done

    echo "Uploading the result file $result_file to the cloud storage..."
    az storage blob upload --account-name $storage_account --auth-mode login --overwrite \
        --container-name $container_name --file $result_file --name "${TF_VAR_run_id}.json"
}

# Main
confirm "publish_results"
publish_results
