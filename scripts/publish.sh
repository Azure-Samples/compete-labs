#!/bin/bash

source scripts/utils.sh

PROVIDER=$1
AWS_HOURLY_COST=32.7726
AZURE_HOURLY_COST=14.69

publish_results() {
    local result_file="/tmp/${TF_VAR_run_id}-result.json"
    local storage_account="akstelescope"
    local container_name="compete-labs"
    local cloud_info=$(jq -n \
        --arg provider "$PROVIDER" \
        --arg region "$TF_VAR_region" \
        '{provider: $provider, region: $region}')
    local total_cost=0.0

    steps="provision validate deploy start test cleanup"
    for step in $steps; do
        status_var=$(echo "${step}_STATUS" | tr '[:lower:]' '[:upper:]')
        latency_var=$(echo "${step}_LATENCY" | tr '[:lower:]' '[:upper:]')
        error_var=$(echo "${step}_ERROR" | tr '[:lower:]' '[:upper:]')
        cost_var=$(echo "${PROVIDER}_HOURLY_COST" | tr '[:lower:]' '[:upper:]')
        cost=$(awk "BEGIN {printf \"%.4f\", ${!cost_var} * ${!latency_var} / 3600}")
        total_cost=$(awk "BEGIN {printf \"%.4f\", $total_cost + $cost}")

        eval "step_info=\$(jq -n \
            --arg status \"\${!status_var}\" \
            --arg latency \"\${!latency_var}\" \
            --arg error \"\${!error_var}\" \
            --arg cost \"$cost\" \
            '{status: \$status, latency: \$latency, error: \$error, cost_in_usd: \$cost}')"
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

    # One entry for total cost
    step_info=$(jq -n \
        --arg total_cost "$total_cost" \
        '{
            cost_in_usd: $total_cost
        }')
    echo "Processed total cost: $step_info"
    result=$(jq -n \
            --arg timestamp "$(date +%s)" \
            --arg run_id "$TF_VAR_run_id" \
            --arg owner "$USER_ALIAS" \
            --arg cloud_info "$cloud_info" \
            --arg step "summary" \
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

    echo "Uploading the result file $result_file to the cloud storage..."
    az storage blob upload --account-name $storage_account --auth-mode login --overwrite \
        --container-name $container_name --file $result_file --name "${TF_VAR_run_id}-${PROVIDER}.json"

    echo -e "${GREEN}Congratulations $USER_ALIAS on completing the $PROVIDER section of Compete Lab!"
}

# Main
confirm "publish_results"
publish_results
