#!/bin/bash

source scripts/utils.sh

# Check if action and cloud are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <action> <cloud>"
  echo "Action options: deploy, start, test"
  echo "Cloud options: aws, azure"
  exit 1
fi

ACTION=$1
CLOUD=$2

export TIMEOUT=300
export POLLING_INTERVAL=3
export USERNAME="ubuntu"
export SSH_PORT=2222

get_public_ip_azure() {
    echo "Getting the public IP address..."
    public_ip_name=$(az network public-ip list --resource-group "compete-labs-$TF_VAR_owner" \
        --query "[0].name" --output tsv)
    public_ip=$(az network public-ip show --resource-group "compete-labs-$TF_VAR_owner" \
        --name $public_ip_name --query "ipAddress" --output tsv)
    echo "Public IP: $public_ip"
    export PUBLIC_IP=$public_ip
}

get_public_ip_aws() {
    echo "Getting the public IP address..."
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
    local extra_options=$6

    sshCommand="ssh $extra_options -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $privatekey_path -p $port $user@$ip $command"
    $sshCommand
}

validate_resources() {
    local command="nvidia-smi"
    local error_file="/tmp/${TF_VAR_run_id}-validate_resources-error.txt"

    echo "Validating the resources..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    while true; do
        run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            echo "Resources are validated successfully!"
            export VALIDATE_STATUS="Success"
            export VALIDATE_LATENCY=$(($(date +%s) - $start_time))
            break
        fi

        if [ $(date +%s) -gt $timeout_time ]; then
            export VALIDATE_STATUS="Failure"
            export VALIDATE_LATENCY=$(($(date +%s) - $start_time))
            export VALIDATE_ERROR=$(cat $error_file)
            echo "Validating the resources failed with error: ${VALIDATE_ERROR}"
            break
        fi

        echo "Wait for $POLLING_INTERVAL seconds before validating the resources..."
        sleep $POLLING_INTERVAL
    done

    echo "Validation status: $VALIDATE_STATUS, Validation latency: $VALIDATE_LATENCY seconds"
}

deploy_server() {
    local command="sudo docker pull vllm/vllm-openai:v0.6.3.post1"
    local error_file="/tmp/${TF_VAR_run_id}-deploy_server-error.txt"

    echo "Deploying the server..."
    start_time=$(date +%s)
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" "-t" 2> $error_file
    local exit_code=$?
    end_time=$(date +%s)
    export DEPLOY_LATENCY=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        echo "Server is deployed successfully!"
        export DEPLOY_STATUS="Success"
    else
        export DEPLOY_STATUS="Failure"
        export DEPLOY_ERROR=$(cat $error_file)
        echo "Deploying the server failed with error: ${DEPLOY_ERROR}"
    fi
    echo "Deploy status: $DEPLOY_STATUS, Deploy latency: $DEPLOY_LATENCY seconds"
}

start_server() {
    echo "Cleaning up existing containers (if any) before starting the server..."
    local cleanup_command="sudo docker stop \$(sudo docker ps -aq) && sudo docker rm \$(sudo docker ps -aq)"
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$cleanup_command" 2> /dev/null

    local run_command="sudo docker run -d \
        --runtime nvidia \
        --gpus all \
        -v ~/.cache/huggingface:/root/.cache/huggingface \
        --env "HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_TOKEN}" \
        --env "VLLM_API_KEY=${VLLM_API_KEY}" \
        -p 80:80 \
        --ipc=host \
        vllm/vllm-openai:v0.6.3.post1 \
        --model meta-llama/Meta-Llama-3.1-8B \
        --max_model_len 10000 \
        --port 80"
    local error_file="/tmp/${TF_VAR_run_id}-start_server-error.txt"
    local complete_line="Application startup complete"

    echo "Starting the server..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    container_id=$(run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$run_command" 2> $error_file)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "Container ID: $container_id"
        local log_command="sudo docker logs $container_id"

        while true; do
            echo "Checking the server logs..."
            response=$(run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$log_command" "-tt" 2> $error_file)
            echo "$response"
            if [[ $response == *"$complete_line"* ]]; then
                echo "Server is started successfully!"
                export START_STATUS="Success"
                export START_LATENCY=$(($(date +%s) - $start_time))
                break
            fi

            if [[ $(date +%s) -gt $timeout_time ]]; then
                echo "Timeout: Cannot start the server!"
                export START_STATUS="Failure"
                export START_LATENCY=$(($(date +%s) - $start_time))
                echo "Checking container logs for more information..."
                run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "sudo docker logs $container_id" 2>&1 | tee -a $error_file
                export START_ERROR=$(cat $error_file)
                break
            fi
            sleep $POLLING_INTERVAL
        done
    else
        export START_STATUS="Failure"
        export START_LATENCY=$(($(date +%s) - $start_time))
        export START_ERROR=$(cat $error_file)
        echo "Starting the server failed with error: ${START_ERROR}"
    fi
    echo "Start status: $START_STATUS, Start latency: $START_LATENCY seconds"
}

test_server() {
    local health_endpoint="http://${PUBLIC_IP}:80/health"
    echo "Checking server health endpoint at $health_endpoint ..."
    response=$(curl -s -o /dev/null -w "%{http_code}" $health_endpoint)
    if [ $response -eq 200 ]; then
        echo "Server is healthy!"

        local completion_endpoint="http://${PUBLIC_IP}:80/v1/completions"
        local prompt="You are a helpful assistant. Tell me a joke."
        local data="{\"model\": \"meta-llama/Meta-Llama-3.1-8B\", \"prompt\": \"$prompt\", \"temperature\": 0.7, \"top_k\": -1, \"max_tokens\": 9900}"
        local error_file="/tmp/${TF_VAR_run_id}-test_server-error.txt"
        local response_file="/tmp/${TF_VAR_run_id}-test_server-response.txt"

        echo "Testing the server with request data $data ..."
        start_time=$(date +%s)
        status_code=$(curl -o $response_file -w "%{http_code}" \
            -X POST $completion_endpoint \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${VLLM_API_KEY}" \
            -d "$data" 2> $error_file)
        local exit_code=$?
        end_time=$(date +%s)
        export TEST_LATENCY=$((end_time - start_time))

        if [[ $exit_code -eq 0 ]]; then
            if [[ $status_code -eq 200 ]]; then
                cat $response_file
                echo "Server is tested successfully!"
                export TEST_STATUS="Success"
            else
                export TEST_STATUS="Failure"
                export TEST_ERROR=$(cat $response_file)
                echo "Testing the server failed with status code ${status_code} and response: ${TEST_ERROR}"
            fi
        else
            export TEST_STATUS="Failure"
            export TEST_ERROR=$(cat $error_file)
            echo "Testing the server failed with error: ${TEST_ERROR}"
        fi
    else
        echo "Server is not healthy!"
        export TEST_LATENCY=$((end_time - start_time))
        export TEST_STATUS="Failure"
        export TEST_ERROR="Server is not healthy!"
    fi

    echo "Test status: $TEST_STATUS, Test latency: $TEST_LATENCY seconds"
}

# Main
case $ACTION in
    deploy)
        get_public_ip_${CLOUD}
        validate_resources
        deploy_server
        ;;
    start)
        start_server
        ;;
    test)
        test_server
        ;;
    *)
        echo "Invalid action: $ACTION"
        exit 1
        ;;
esac