#!/bin/bash

# Function to prompt user for confirmation
confirm() {
    while true; do
        read -p "Proceed with $1? (y): " choice
        case "$choice" in 
            y|Y ) echo "Proceeding with $1..."; return 0;;
            * ) echo "Invalid input. Please type 'y' to proceed.";;
        esac
    done
}

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

publish_results() {
  AWS_HOURLY_COST=32.7726
  AZURE_HOURLY_COST=14.69
  local step=$1
  local PROVIDER=$2
  local result_file="/tmp/${USER_ALIAS}-${PROVIDER}-result.json"
  export result_file
  local cloud_info=$(jq -n \
      --arg provider "$PROVIDER" \
      --arg region "$TF_VAR_region" \
      '{provider: $provider, region: $region}')

  status_var=$(echo "${step}_STATUS" | tr '[:lower:]' '[:upper:]')
  latency_var=$(echo "${step}_LATENCY" | tr '[:lower:]' '[:upper:]')
  error_var=$(echo "${step}_ERROR" | tr '[:lower:]' '[:upper:]')
  cost_var=$(echo "${PROVIDER}_HOURLY_COST" | tr '[:lower:]' '[:upper:]')
  cost=$(awk "BEGIN {printf \"%.4f\", ${!cost_var} * ${!latency_var} / 3600}")

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
}