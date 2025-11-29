provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket  = "terra-backend-sagi"
    key     = "FlaskApp/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

variable "rds_user" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "rds_pass" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# -------------------
# VPC
# -------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

# NAT Gateway (Elastic IP)
resource "aws_eip" "nat" {
  vpc = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet1.id
}

# Private Route Table (for RDS subnet)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-rt" }
}

# -------------------
# Subnets
# -------------------
# Public Subnets
resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags                     = { Name = "public-subnet-1" }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags                     = { Name = "public-subnet-2" }
}

# Private Subnets (for RDS)
resource "aws_subnet" "private_subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "private-subnet-1" }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-subnet-2" }
}

# Associate Route Tables
resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private_subnet1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private_subnet2.id
  route_table_id = aws_route_table.private.id
}

# -------------------
# Security Groups
# -------------------
# EC2 SG
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-flask-sg"
  description = "Allow SSH + Flask app"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
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

# RDS SG
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL access from EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------
# IAM Role + Profile for EC2
# -------------------
resource "aws_iam_role" "ec2_role" {
  name = "ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_instance_connect" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2InstanceConnect"
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# -------------------
# RDS Subnet Group
# -------------------
resource "aws_db_subnet_group" "flask_db" {
  name       = "flask-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet1.id,
    aws_subnet.private_subnet2.id
  ]
  tags = { Name = "flask-db-subnet-group" }
}

# -------------------
# RDS Instance
# -------------------
resource "aws_db_instance" "flask_db" {
  identifier             = "flask-app-db"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.43"
  username               = var.rds_user
  password               = var.rds_pass
  port                   = 3306
  db_subnet_group_name   = aws_db_subnet_group.flask_db.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  backup_retention_period = 1
}

# -------------------
# EC2 Instance
# -------------------
resource "aws_instance" "flask_ec2" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet1.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y docker awscli
  systemctl enable docker
  systemctl start docker
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  # Login to ECR
  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 340063596901.dkr.ecr.us-east-1.amazonaws.com

  # Run container
  docker pull 340063596901.dkr.ecr.us-east-1.amazonaws.com/flask-web-app:latest
  docker run -d -p 5000:5000 \
    -e DB_HOST="${aws_db_instance.flask_db.endpoint}" \
    -e DB_USER="${var.rds_user}" \
    -e DB_PASS="${var.rds_pass}" \
    340063596901.dkr.ecr.us-east-1.amazonaws.com/flask-web-app:latest
  EOF

  tags = { Name = "flask-ec2" }
}

# -------------------
# Outputs
# -------------------
output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}

output "db_endpoint" {
  value = aws_db_instance.flask_db.endpoint
}
