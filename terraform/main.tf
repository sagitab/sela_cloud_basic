provider "aws" {
  region = "us-east-1"
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