#!/bin/bash

PROVIDER=$1

export TIMEOUT=600
export USERNAME="ubuntu"
export SSH_PORT=2222

get_public_ip_azure() {
    public_ip_name=$(az network public-ip list --resource-group $TF_VAR_run_id \
        --query "[0].name" --output tsv)
    public_ip=$(az network public-ip show --resource-group $TF_VAR_run_id \
        --name $public_ip_name --query "ipAddress" --output tsv)
    echo "Public IP: $public_ip"
    export PUBLIC_IP=$public_ip
}

get_public_ip_aws() {
    public_ip=$(aws ec2 describe-instances --region $TF_VAR_region \
        --filters Name=tag:run_id,Values=${TF_VAR_run_id} Name=instance-state-name,Values=running \
        --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    echo "Public IP: $public_ip"
    export PUBLIC_IP=$public_ip
}

run_ssh_command() {
  local privatekey_path=$1
  local user=$2
  local ip=$3
  local port=$4
  local command=$5

  sshCommand="ssh -i $privatekey_path -A -p $port $user@$ip -2 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o ConnectTimeout=5 -o GSSAPIAuthentication=no -o ServerAliveInterval=30 -o ServerAliveCountMax=10 $command"
  $sshCommand
}

deploy_server() {
    local command="sudo docker pull vllm/vllm-openai:v0.6.3.post1"
    local error_file="/tmp/${TF_VAR_run_id}-deploy_server-error.txt"

    echo "Deploying the server..."
    start_time=$(date +%s)
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file
    local exit_code=$?
    end_time=$(date +%s)
    export DEPLOY_LATENCY=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        echo "Server is deployed successfully!"
        export DEPLOY_STATUS="Success"
    else
        echo "Error: Cannot pull the docker image!"
        export DEPLOY_STATUS="Failure"
        export DEPLOY_ERROR=$(cat $error_file)
    fi
    echo "Deploy status: $DEPLOY_STATUS, Deploy latency: $DEPLOY_LATENCY seconds"
}

start_server() {
    if [[ "$DEPLOY_STATUS" != "Success" ]]; then
        echo "Skip starting the server due to the deployment failure!"
        export START_STATUS="Skipped"
        export START_LATENCY=-1
        return
    fi

    local command="sudo docker run -d \
        --runtime nvidia \
        --gpus all \
        -v ~/.cache/huggingface:/root/.cache/huggingface \
        --env "HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_TOKEN}" \
        --env "VLLM_API_KEY=${VLLM_API_KEY}" \
        -p 8000:8000 \
        --ipc=host \
        vllm/vllm-openai:v0.6.3.post1 \
        --model meta-llama/Meta-Llama-3.1-8B \
        --max_model_len 10000"
    local error_file="/tmp/${TF_VAR_run_id}-start_server-error.txt"

    echo "Starting the server..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local health_endpoint="http://${PUBLIC_IP}:8000/health"
        local polling_interval=5

        while true; do
            response=$(curl -v -s -o /dev/null -w "%{http_code}" $health_endpoint)
            if [ $response -eq 200 ]; then
                echo "Server is started successfully!"
                export START_STATUS="Success"
                export START_LATENCY=$(($(date +%s) - $start_time))
                break
            fi

            if [ $(date +%s) -gt $timeout_time ]; then
                echo "Timeout: Cannot start the server!"
                export START_STATUS="Failure"
                export START_ERROR="Cannot start the server!"
                export START_LATENCY=$(($(date +%s) - $start_time))
                break
            fi

            echo "Wait for $polling_interval seconds before checking the server status..."
            sleep $polling_interval
        done
    else
        echo "Error: Cannot start the server!"
        export START_STATUS="Failure"
        export START_ERROR=$(cat $error_file)
    fi
    echo "Start status: $START_STATUS, Start latency: $START_LATENCY seconds"
}

test_server() {
    if [[ "$START_STATUS" != "Success" ]]; then
        echo "Skip testing the server due to the start failure!"
        export TEST_STATUS="Skipped"
        export TEST_LATENCY=-1
        return
    fi

    local completion_endpoint="http://${PUBLIC_IP}:8000/v1/completions"
    local prompt="You are a helpful assistant. Tell me a joke."
    local data="{\"model\": \"meta-llama/Meta-Llama-3.1-8B\", \"prompt\": \"$prompt\", \"temperature\": 0.7, \"top_k\": -1, \"max_tokens\": 9900}"

    echo "Testing the server..."
    start_time=$(date +%s)
    response=$(curl -X POST $completion_endpoint \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${VLLM_API_KEY}" \
        -d "$data")
    local exit_code=$?
    end_time=$(date +%s)
    export TEST_LATENCY=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        echo $response
        echo "Server is tested successfully!"
        export TEST_STATUS="Success"
    else
        echo "Error: Cannot test the server!"
        export TEST_STATUS="Failure"
    fi
    echo "Test status: $TEST_STATUS, Test latency: $TEST_LATENCY seconds"
}

publish_results() {
    local result_file="/tmp/${TF_VAR_run_id}-result.json"
    local storage_account="akstelescope"
    local container_name="compete-labs"

    steps="deploy start test"
    for step in $steps; do
        status_var="${step^^}_STATUS"
        latency_var="${step^^}_LATENCY"
        error_var="${step^^}_ERROR"

        eval "${step}_info=\$(jq -n \
            --arg status \"\${!status_var}\" \
            --arg latency \"\${!latency_var}\" \
            --arg error \"\${!error_var}\" \
            '{status: \$status, latency: \$latency, error: \$error}')"
        eval echo "${step^^}_INFO: \${${step}_info}"
    done

    data=$(jq -n \
        --arg provision "$PROVISION_INFO" \
        --arg deploy "$deploy_info" \
        --arg start "$start_info" \
        --arg test "$test_info" \
        --arg destroy "$DESTROY_INFO" \
        '{provision: $provision, deploy: $deploy, start: $start, test: $test, destroy: $destroy}')

    result=$(jq -n \
        --arg owner "$USER_ALIAS" \
        --arg cloud_info "$CLOUD_INFO" \
        --arg lab_info "$LAB_INFO" \
        --arg result "$data" \
        '{owner: $owner, cloud_info: $cloud_info, lab_info: $lab_info, result: $result}')

    echo "Result: $result"

    echo $result > $result_file
    echo "Upload the result file to the cloud storage..."
    az storage blob upload --account-name $storage_account --auth-mode login --overwrite \
        --container-name $container_name --file $result_file --name "${TF_VAR_run_id}.json"
}

#Main
get_public_ip_${PROVIDER}
deploy_server
start_server
test_server
publish_results