#!/bin/bash

source scripts/utils.sh

PROVIDER=$1

export TIMEOUT=600
export POLLING_INTERVAL=3
export USERNAME="ubuntu"
export SSH_PORT=2222

get_public_ip_azure() {
    public_ip_name=$(az network public-ip list --resource-group "compete-labs-$TF_VAR_owner" \
        --query "[0].name" --output tsv)
    public_ip=$(az network public-ip show --resource-group "compete-labs-$TF_VAR_owner" \
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
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file
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
        -p 80:80 \
        --ipc=host \
        vllm/vllm-openai:v0.6.3.post1 \
        --model meta-llama/Meta-Llama-3.1-8B \
        --max_model_len 10000 \
        --port 80"
    local error_file="/tmp/${TF_VAR_run_id}-start_server-error.txt"
    
    echo "Starting the server..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    container_id=$(run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        local health_endpoint="http://${PUBLIC_IP}:80/health"

        while true; do
            response=$(curl -s -o /dev/null -w "%{http_code}" $health_endpoint)
            if [ $response -eq 200 ]; then
                echo "Server is started successfully!"
                export START_STATUS="Success"
                export START_LATENCY=$(($(date +%s) - $start_time))
                break
            fi

            if [ $(date +%s) -gt $timeout_time ]; then
                echo "Timeout: Cannot start the server!"
                export START_STATUS="Failure"
                export START_LATENCY=$(($(date +%s) - $start_time))
                echo "Checking container logs for more information..."
                run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "sudo docker logs $container_id" 2>&1 | tee -a $error_file
                export START_ERROR=$(cat $error_file)
                break
            fi
            
            echo "Wait for $POLLING_INTERVAL seconds before checking the server status..."
            sleep $POLLING_INTERVAL
        done
    else
        export START_STATUS="Failure"
        export START_ERROR=$(cat $error_file)
        
        echo "Starting the server failed with error: ${START_ERROR}"
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
    echo "Test status: $TEST_STATUS, Test latency: $TEST_LATENCY seconds"
}

# Main
confirm "get_public_ip_${PROVIDER}"
get_public_ip_${PROVIDER}

confirm "validate_resources"
validate_resources

confirm "deploy_server"
deploy_server

confirm "start_server"
start_server

confirm "test_server"
test_server
