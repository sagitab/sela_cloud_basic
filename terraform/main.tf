provider "aws" {
  region = "us-east-1"
}
terraform {
  backend "s3" {
    bucket         = "terra-backend-sagi"  # your bucket
    key            = "FlaskApp/terraform.tfstate" # path inside bucket
    region         = "us-east-1"
    encrypt        = true
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
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-flask-sg"
  description = "Allow SSH + HTTP"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flask app
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
resource "aws_iam_role" "ec2_role" {
  name = "ec2-instance-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "ssm_read_policy" {
  name = "ssm-read-policy"
  role = aws_iam_role.ec2_role.name  # use .name, not .id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:us-east-1:parameter/flask-app/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_instance_connect" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceConnect"
}
resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-connect-profile"
  role = aws_iam_role.ec2_role.name
}


# -------------------
# EC2 Instance (cheapest)
# -------------------
resource "aws_instance" "flask_ec2" {
  ami                    = "ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1)
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
  #!/bin/bash
  yum update -y

  # Install docker
  yum install -y docker
  systemctl enable docker
  systemctl start docker

  # Install AWS CLI (already installed on AL2 but ensure it)
  yum install -y awscli

  # Login to ECR
  aws ecr get-login-password --region us-east-1 \
    | docker login --username AWS --password-stdin 340063596901.dkr.ecr.us-east-1.amazonaws.com

  # Pull and run container
  docker pull 340063596901.dkr.ecr.us-east-1.amazonaws.com/flask-web-app:latest

  # Set DB credentials (replace with your real password)
  # Export DB credentials
  RDS_USER=$(aws ssm get-parameter --name "/flask-app/db-user" --with-decryption --query "Parameter.Value" --output text)
  RDS_PASS=$(aws ssm get-parameter --name "/flask-app/db-pass" --with-decryption --query "Parameter.Value" --output text)

  # Run container
  docker run -d -p 5000:5000 \
    -e DB_HOST="flask-app-db.cyh22uwcyfkq.us-east-1.rds.amazonaws.com" \
    -e DB_USER="$RDS_USER" \
    -e DB_PASS="$RDS_PASS" \
    -e DB_NAME="flask_db" \
    340063596901.dkr.ecr.us-east-1.amazonaws.com/flask-web-app:latest
  EOF

  tags = { Name = "flask-ec2" }
}

# Output EC2 Public IP
output "ec2_public_ip" {
  value = aws_instance.flask_ec2.public_ip
}


# -------------------
# Networking (VPC)
# -------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "private-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "main-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# Add these sections to your current file:

# -------------------
# RDS Security Group
# -------------------
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow MySQL access"
  vpc_id      = aws_vpc.main.id  # Reference your existing VPC

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Or restrict to your VPC: [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# -------------------
# RDS Instance
# -------------------
resource "aws_db_instance" "flask_db" {
  identifier     = "flask-app-db"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  storage_type   = "gp2"
  
  engine               = "mysql"
  engine_version       = "8.0.43"
  
  # Use your existing variables
  username = var.rds_user
  password = var.rds_pass
  port     = 3306
  
  # Network references
  db_subnet_group_name   = aws_db_subnet_group.flask_db.name  # Reference subnet group
  vpc_security_group_ids = [aws_security_group.rds_sg.id]     # Reference security group
  publicly_accessible    = true
  
  # Basic settings
  skip_final_snapshot     = true
  backup_retention_period = 1
  
  tags = {
    Name = "flask-app-db"
  }
}
# Add second private subnet in different AZ
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-subnet-b" }
}

# -------------------
# Public Subnets
# -------------------
resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.11.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = {
    Name = "public-subnet-2"
  }
}
resource "aws_route_table_association" "public_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_subnet2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public.id
}


# Update subnet group with multiple AZs
resource "aws_db_subnet_group" "flask_db" {
  name       = "flask-db-subnet-group-new"
  subnet_ids = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]  # 2 different AZs!
  tags = { Name = "flask-db-subnet-group-new" }
}

# -------------------
# RDS Outputs
# -------------------
output "db_endpoint" {
  description = "RDS endpoint for application connection"
  value       = aws_db_instance.flask_db.endpoint
}

output "db_connection_string" {
  description = "Full connection string"
  value       = "mysql://${var.rds_user}:${var.rds_pass}@${aws_db_instance.flask_db.endpoint}"
  sensitive   = true
}



