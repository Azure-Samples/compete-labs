locals {
  tags = {
    "Name"              = "compete-labs-${var.owner}"
    "deletion_due_time" = timeadd(plantimestamp(), "8h")
    "owner"             = var.owner
    "run_id"            = var.run_id
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}${var.zone_suffix}"
}

resource "aws_security_group" "sg" {
  name        = "chatbot-sg"
  description = "Security group for chatbot server"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "route_tables" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table_association" "route_table_association" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_tables.id
}

data "aws_ami" "deep_learning_gpu_ami" {
  most_recent = true
  owners      = ["898082745236"]
  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) 20241025"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "admin_key_pair" {
  key_name   = "admin-key-pair-${var.run_id}"
  public_key = file(var.ssh_public_key)
}

resource "aws_instance" "vm" {
  ami                         = data.aws_ami.deep_learning_gpu_ami.id
  instance_type               = "g4dn.12xlarge"
  availability_zone           = "${var.region}${var.zone_suffix}"
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.admin_key_pair.key_name
  user_data                   = file(var.user_data_path)
  root_block_device {
    volume_size = 256
  }
}
