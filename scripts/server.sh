#!/bin/bash

source scripts/utils.sh

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${RED}This script must be sourced. Run it with: source $0${NC}"
    exit 0
fi

# Check if action and cloud are provided
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <action> <cloud>"
  echo "Action options: deploy, start, test"
  echo "Cloud options: aws, azure"
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
    echo -e "${GREEN}Public IP: $public_ip${NC}"
    export PUBLIC_IP=$public_ip
}

get_public_ip_aws() {
    echo "Getting the public IP address..."
    public_ip=$(aws ec2 describe-instances --region $TF_VAR_region \
        --filters Name=tag:owner,Values=${TF_VAR_owner} Name=instance-state-name,Values=running \
        --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    echo -e "${GREEN}Public IP: $public_ip${NC}"
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
    export VALIDATE_LATENCY="" VALIDATE_STATUS="" VALIDATE_ERROR=""
    local command="nvidia-smi"
    local error_file="/tmp/${TF_VAR_run_id}/${CLOUD}/validate_resources-error.txt"
    mkdir -p "$(dirname "$error_file")"

    echo "Validating the resources..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    while true; do
        run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" 2> $error_file
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}Resources are validated successfully!${NC}"
            export VALIDATE_STATUS="Success"
            export VALIDATE_LATENCY=$(($(date +%s) - $start_time))
            break
        fi

        if [ $(date +%s) -gt $timeout_time ]; then
            export VALIDATE_STATUS="Failure"
            export VALIDATE_LATENCY=$(($(date +%s) - $start_time))
            export VALIDATE_ERROR=$(cat $error_file)
            echo -e "${RED}Validating the resources failed with error: ${VALIDATE_ERROR}${NC}"
            break
        fi

        echo "Wait for $POLLING_INTERVAL seconds before validating the resources..."
        sleep $POLLING_INTERVAL
    done

    echo -e "${YELLOW}Validation status: $VALIDATE_STATUS, Validation latency: $VALIDATE_LATENCY seconds${NC}"
    publish_results "validate" $CLOUD
}

deploy_server() {
    export DEPLOY_LATENCY="" DEPLOY_STATUS="" DEPLOY_ERROR=""
    local model="vllm/vllm-openai:v0.6.3.post1"
    local command="sudo docker pull $model"
    local error_file="/tmp/${TF_VAR_run_id}/${CLOUD}/deploy_server-error.txt"
    mkdir -p "$(dirname "$error_file")"

    echo "Deploying the server with model ${model}..."
    start_time=$(date +%s)
    run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$command" "-t" 2> $error_file
    local exit_code=$?
    end_time=$(date +%s)
    export DEPLOY_LATENCY=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}Server is deployed successfully!${NC}"
        export DEPLOY_STATUS="Success"
    else
        export DEPLOY_STATUS="Failure"
        export DEPLOY_ERROR=$(cat $error_file)
        echo -e "${RED}Deploying the server failed with error: ${DEPLOY_ERROR}${NC}"
    fi
    echo -e "${YELLOW}Deploy status: $DEPLOY_STATUS, Deploy latency: $DEPLOY_LATENCY seconds${NC}"
    publish_results "deploy" $CLOUD
}

start_server() {
    export START_LATENCY="" START_STATUS="" START_ERROR=""
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
        --dtype float16 \
        --tensor-parallel-size 2 \
        --port 80"
    local error_file="/tmp/${TF_VAR_run_id}/${CLOUD}/start_server-error.txt"
    mkdir -p "$(dirname "$error_file")"
    local complete_line="Application startup complete"

    echo "Starting the server..."
    start_time=$(date +%s)
    timeout_time=$((start_time + TIMEOUT))
    container_id=$(run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$run_command" 2> $error_file)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}Container ID: $container_id${NC}"
        local log_command="sudo docker logs --tail 10 $container_id"

        while true; do
            echo "Checking the server logs..."
            response=$(run_ssh_command $SSH_KEY_PATH $USERNAME $PUBLIC_IP $SSH_PORT "$log_command" "-tt" 2> $error_file)
            echo "$response"
            if [[ $response == *"$complete_line"* ]]; then
                echo -e "${GREEN}Server is started successfully!${NC}"
                export START_STATUS="Success"
                export START_LATENCY=$(($(date +%s) - $start_time))
                break
            fi

            if [[ $(date +%s) -gt $timeout_time ]]; then
                echo -e "${RED}Timeout: Cannot start the server!${NC}"
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
        echo -e "${RED}Starting the server failed with error: ${START_ERROR}${NC}"
    fi
    echo -e "${YELLOW}Start status: $START_STATUS, Start latency: $START_LATENCY seconds${NC}"
    publish_results "start" $CLOUD
}

test_server() {
    export TEST_LATENCY="" TEST_STATUS="" TEST_ERROR=""
    local Q1="If turkeys could talk, what do you think they would say to convince us to eat something else for Thanksgiving dinner?"
    local Q2="If Santa's reindeer went on strike, which animals would he recruit to pull his sleigh, and why?"
    local Q3="What would happen if Santa Claus and a Thanksgiving turkey switched places for a day?"

    local health_endpoint="http://${PUBLIC_IP}:80/health"
    echo "Checking server health endpoint at $health_endpoint ..."
    response=$(curl -s -o /dev/null -w "%{http_code}" $health_endpoint)
    if [ $response -eq 200 ]; then
        echo -e "${GREEN}Server is healthy!${NC}"

        echo "Please choose a question:"
        echo "1) $Q1"
        echo "2) $Q2"
        echo "3) $Q3"
        read -p "Enter the number of your choice: " choice

        case $choice in
            1)
                local question=$Q1
                ;;
            2)
                local question=$Q2
                ;;
            3)
                local question=$Q3
                ;;
            *)
                echo "Invalid choice. Will default to the first question."
                local question=$Q1
                ;;
        esac

        local completion_endpoint="http://${PUBLIC_IP}:80/v1/completions"
        local prompt="You are a helpful assistant. Help me answer this question: $question"
        local body="{\"model\": \"meta-llama/Meta-Llama-3.1-8B\", \"prompt\": \"$prompt\", \"temperature\": 0.7, \"top_k\": -1, \"max_tokens\": 1000, \"stream\": true, \"stream_options\": {\"include_usage\": true}}"
        local error_file="/tmp/${TF_VAR_run_id}-test_server-error.txt"
        local response_file="/tmp/${TF_VAR_run_id}-test_server-response.json"
        rm $response_file 2> /dev/null

        echo "Question: $question"
        echo "Answer:"

        start_time=$(date +%s)
        while IFS= read -r line; do
            if [ -z "$line" ] || [ "$line" == " " ]; then
                continue
            fi
            echo "$line" >> $response_file
            data=$(echo "$line" | sed 's/^data: //')
            word=$(echo $data | jq -r '.choices[0].text')
            printf "%s" "$word"

            finish_reason=$(echo $data | jq -r '.choices[0].finish_reason')
            if [ "$finish_reason" != "null" ]; then
                usage=$(echo $data | jq -r '.usage')
                break
            fi
        done < <(curl -s -X POST $completion_endpoint \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${VLLM_API_KEY}" \
            -d "$body")

        local exit_code=$?
        end_time=$(date +%s)
        export TEST_LATENCY=$((end_time - start_time))

        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}\nUsage: $usage${NC}"
            echo -e "${GREEN}Server is tested successfully!${NC}"
            export TEST_STATUS="Success"
        else
            export TEST_STATUS="Failure"
            export TEST_ERROR=$(cat $error_file)
            echo -e "${RED}Testing the server failed with error: ${TEST_ERROR}${NC}"
        fi
    else
        echo -e "${RED}Server is not healthy!${NC}"
        export TEST_LATENCY=$((end_time - start_time))
        export TEST_STATUS="Failure"
        export TEST_ERROR="Server is not healthy!"
    fi

    echo -e "${YELLOW}Test status: $TEST_STATUS, Test latency: $TEST_LATENCY seconds${NC}"
    publish_results "test" $CLOUD
}

# Main
case $ACTION in
    deploy)
        get_public_ip_${CLOUD}
        validate_resources
        confirm "deploy_server"
        deploy_server
        ;;
    start)
        confirm "start_server"
        start_server
        ;;
    test)
        test_server
        ;;
    *)
        echo "Invalid action: $ACTION"
        ;;
esac