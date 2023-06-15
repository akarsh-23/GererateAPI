# Define variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  default     = "ap-south-1"
}

variable "application_name" {
  description = "Name of the Node.js application"
  default     = "generate-api"
}

# Configure AWS provider
provider "aws" {
  region = var.aws_region
}

# Create ECR repository
resource "aws_ecr_repository" "ecr_repository" {
  name = "${var.application_name}-ecr-repo"
}

# Create CloudWatch Logs log group
resource "aws_cloudwatch_log_group" "log_group" {
  name = "/ecs/${var.application_name}"
  retention_in_days = 7  # Adjust the retention period as needed
}

# Create ECS task definition
resource "aws_ecs_task_definition" "task_definition" {
  family                   = "${var.application_name}-task"
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 256
  memory = 512

  container_definitions = <<EOF
[
  {
    "name": "${var.application_name}",
    "image": "${aws_ecr_repository.ecr_repository.repository_url}:latest",
    "portMappings": [
      {
        "containerPort": 80,
        "protocol": "tcp"
      }
    ],
    "essential": true,
    "cpu": 256,
    "memory": 512,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.log_group.name}",
        "awslogs-region": "${var.aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]
EOF
}

# Create ECS service
resource "aws_ecs_service" "service" {
  name            = "${var.application_name}-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = ["subnet-052cdd25b746050e9", "subnet-0939a1c25b1c0492c", "subnet-0e6fa14ea84ea8e2e"]
    security_groups = [aws_security_group.ecs_security_group.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.lb_target_group.arn
    container_name   = var.application_name
    container_port   = 80
  }
}

# Create ECS cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.application_name}-cluster"
}

# Create Application Load Balancer
resource "aws_lb" "lb" {
  name               = "${var.application_name}-lb"
  load_balancer_type = "application"
  subnets            = ["subnet-052cdd25b746050e9", "subnet-0939a1c25b1c0492c", "subnet-0e6fa14ea84ea8e2e"]
  security_groups    = [aws_security_group.elb_security_group.id]
}

# Create Target Group with instance target type
resource "aws_lb_target_group" "lb_target_group" {
  name        = "${var.application_name}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id
}

# Create listener for ALB
resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.lb_target_group.arn
    type             = "forward"
  }
}

# Retrieve default VPC and subnet IDs
data "aws_vpc" "default" {
  default = true
}

# Create security group for ECS tasks
resource "aws_security_group" "ecs_security_group" {
  name        = "${var.application_name}-ecs-security-group"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Create security group for ELB
resource "aws_security_group" "elb_security_group" {
  name        = "${var.application_name}-elb-security-group"
  description = "Security group for elb"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Create IAM role for ECS task execution
resource "aws_iam_role" "task_execution_role" {
  name = "${var.application_name}-task-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach policies to the task execution role
resource "aws_iam_role_policy_attachment" "task_execution_policy_attachment" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

