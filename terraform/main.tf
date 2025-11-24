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

# -------------------
# ECS Cluster
# -------------------
resource "aws_ecs_cluster" "flask" {
  name = "sagi-flask-web-app-cluster"
}

# -------------------
# ECS Task Definition
# -------------------
resource "aws_ecs_task_definition" "flask" {
  family                   = "flask-web-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::340063596901:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "flask-web-app"
      image     = "340063596901.dkr.ecr.us-east-1.amazonaws.com/flask-web-app:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# -------------------
# ECS Service
# -------------------
resource "aws_ecs_service" "flask" {
  name            = "flask-web-app-task-service"
  cluster         = aws_ecs_cluster.flask.id
  task_definition = aws_ecs_task_definition.flask.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.flask_sg.id] # use .id, not name
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
}
resource "aws_security_group" "flask_sg" {
  name        = "flask-web-app-sg"
  description = "Allow HTTP traffic"
  vpc_id      = aws_vpc.main.id

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

# RDS

variable "db_name" {
  default = "flaskdb"
}
# --- Security group for DB ---
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow access to MySQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # allow MySQL from anywhere for testing
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-subnet-b" }
}
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = { Name = "public-subnet-b" }
}
# subnet group
resource "aws_db_subnet_group" "flask_db_subnets" {
  name        = "flask-db-subnet-group"
  description = "Private subnets for Flask RDS"
  subnet_ids  = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]
}
# --- RDS instance ---
resource "aws_db_instance" "flask_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.rds_user
  password             = var.rds_pass
  publicly_accessible  = true
  skip_final_snapshot  = true
  port                 = 3306

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.flask_db_subnets.name

  tags = {
    Name = "FlaskApp-DB"
  }
}

# --- Output ---
output "db_endpoint" {
  value = aws_db_instance.flask_db.endpoint
}

output "db_port" {
  value = aws_db_instance.flask_db.port
}



