terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Only used with an emulator; real AWS reads credentials from the environment.
  access_key                  = var.use_emulator ? "test" : null
  secret_key                  = var.use_emulator ? "test" : null
  skip_credentials_validation = var.use_emulator
  skip_metadata_api_check     = var.use_emulator
  skip_requesting_account_id  = var.use_emulator

  dynamic "endpoints" {
    for_each = var.use_emulator ? [1] : []
    content {
      ec2 = var.emulator_endpoint
    }
  }

  default_tags {
    tags = {
      Project   = "devops-practice-project"
      ManagedBy = "terraform"
    }
  }
}

# ---------- Server preparation script ----------
# Windows editors save CRLF line endings, which break bash on Linux, so remove
# the carriage returns, then put the deployer public key into the script.
locals {
  init_script = replace(
    replace(file("${path.module}/../scripts/init-server.sh"), "\r", ""),
    "DEPLOYER_PUBLIC_KEY=\"\"",
    "DEPLOYER_PUBLIC_KEY=\"${trimspace(var.deployer_public_key)}\""
  )
}

# ---------- Image (Ubuntu 24.04 from Canonical) ----------
data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Network ----------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "task-tracker-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "task-tracker-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "task-tracker-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "task-tracker-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------- Firewall (security group) ----------
resource "aws_security_group" "app" {
  name        = "task-tracker-sg"
  description = "SSH from one IP, HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "task-tracker-sg" }
}

# ---------- SSH key and server ----------
resource "aws_key_pair" "deploy" {
  key_name   = "task-tracker-key"
  public_key = trimspace(var.deployer_public_key)
}

resource "aws_instance" "app" {
  ami                         = coalesce(var.ami_id, one(data.aws_ami.ubuntu[*].id))
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.deploy.key_name
  associate_public_ip_address = true

  user_data                   = local.init_script
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "task-tracker-server" }
}