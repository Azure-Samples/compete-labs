#!/bin/bash
INSTANCE_TYPE="g4dn.12xlarge"
AMI_NAME="Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"
AMI_OWNER="898082745236"

create_vpc_subnet() {
    local owner=$1
    local availability_zone=$2

    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' \
        --output text)

    aws ec2 create-tags --resources $vpc_id --tags "Key=Name,Value=compete-labs-${owner}" "Key=owner,Value=${owner}"

    local subnet_id=$(aws ec2 create-subnet \
        --vpc-id $vpc_id \
        --cidr-block 10.0.1.0/24 \
        --availability-zone $availability_zone \
        --query 'Subnet.SubnetId' \
        --output text)

    aws ec2 modify-subnet-attribute \
        --subnet-id $subnet_id \
        --map-public-ip-on-launch

    aws ec2 create-tags --resources $subnet_id --tags "Key=owner,Value=${owner}"

    echo "$vpc_id:$subnet_id"
}

create_security_group() {
    local vpc_id=$1
    local owner=$2

    local sg_id=$(aws ec2 create-security-group \
        --group-name "chatbot-sg" \
        --description "Security group for chatbot server" \
        --vpc-id $vpc_id \
        --query 'GroupId' \
        --output text)

    aws ec2 create-tags --resources $sg_id --tags "Key=owner,Value=${owner}"

    aws ec2 authorize-security-group-ingress \
        --group-id $sg_id \
        --protocol tcp \
        --port 2222 \
        --cidr 0.0.0.0/0 \
        > /dev/null

    aws ec2 authorize-security-group-ingress \
        --group-id $sg_id \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        > /dev/null

    aws ec2 authorize-security-group-ingress \
        --group-id $sg_id \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        > /dev/null

    aws ec2 authorize-security-group-egress \
        --group-id $sg_id \
        --protocol -1 \
        --port -1 \
        --cidr 0.0.0.0/0 \
        > /dev/null

    echo "$sg_id"
}

create_network_routing() {
    local vpc_id=$1
    local subnet_id=$2
    local owner=$3

    local igw_id=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)

    aws ec2 create-tags --resources $igw_id --tags "Key=owner,Value=${owner}"

    aws ec2 attach-internet-gateway \
        --vpc-id $vpc_id \
        --internet-gateway-id $igw_id \
        > /dev/null

    local route_table_id=$(aws ec2 create-route-table \
        --vpc-id $vpc_id \
        --query 'RouteTable.RouteTableId' \
        --output text)

    aws ec2 create-tags --resources $route_table_id --tags "Key=owner,Value=${owner}"

    aws ec2 create-route \
        --route-table-id $route_table_id \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $igw_id \
        > /dev/null

    aws ec2 associate-route-table \
        --subnet-id $subnet_id \
        --route-table-id $route_table_id \
        > /dev/null
}

create_ec2_instance() {
    local run_id=$1
    local subnet_id=$2
    local sg_id=$3
    local ssh_public_key=$4
    local user_data_path=$5
    local owner=$6

    local ami_id=$(aws ec2 describe-images \
        --owners $AMI_OWNER \
        --filters "Name=name,Values=$AMI_NAME" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)

    aws ec2 import-key-pair \
        --key-name "admin-key-pair-${run_id}" \
        --public-key-material "fileb://${ssh_public_key}"

    local instance_id=$(aws ec2 run-instances \
        --image-id $ami_id \
        --instance-type $INSTANCE_TYPE \
        --subnet-id $subnet_id \
        --security-group-ids $sg_id \
        --key-name "admin-key-pair-${run_id}" \
        --associate-public-ip-address \
        --user-data "file://${user_data_path}" \
        --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":256}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    aws ec2 create-tags --resources $instance_id --tags "Key=owner,Value=${owner}"

    aws ec2 wait instance-running --instance-ids $instance_id

    echo "$instance_id"
}

provision_resources_aws() {
    local run_id=$1
    local owner=$2
    local region=$3
    local ssh_public_key=$4
    local user_data_path=$5

    local availability_zone="${region}a"

    echo "Create VPC and subnet..."
    local vpc_subnet_ids=($(create_vpc_subnet "$owner" "$availability_zone" | tr ':' ' '))
    local vpc_id=${vpc_subnet_ids[0]}
    local subnet_id=${vpc_subnet_ids[1]}
    echo "VPC ID: $vpc_id"
    echo "Subnet ID: $subnet_id"

    echo "Create security group..."
    local sg_id=$(create_security_group "$vpc_id" "$owner")
    echo "Security Group ID: $sg_id"

    echo "Create network routing..."
    create_network_routing "$vpc_id" "$subnet_id" "$owner"

    echo "Create EC2 instance..."
    local instance_id=$(create_ec2_instance "$run_id" "$subnet_id" "$sg_id" "$ssh_public_key" "$user_data_path" "$owner")
    echo "Instance ID: $instance_id"
}
