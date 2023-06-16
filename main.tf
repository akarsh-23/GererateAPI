####################################Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  default     = "ap-south-1"
}

variable "application_name" {
  description = "Name of the Node.js application"
  default     = "generate-api"
}

####################################AWS Provider

# Configure AWS provider
provider "aws" {
  region = var.aws_region
}

####################################AWS VPC

# Retrieve default VPC and subnet IDs
data "aws_vpc" "default" {
  default = true
}

####################################AWS ECR

# Create ECR repository
resource "aws_ecr_repository" "ecr_repository" {
  name = "${var.application_name}-ecr-repo"
}

####################################AWS CloudWatch

# Create CloudWatch Logs log group
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/ecs/${var.application_name}"
  retention_in_days = 7 # Adjust the retention period as needed
}

####################################AWS EC2

# Create Application Load Balancer
resource "aws_lb" "lb" {
  name               = "${var.application_name}-lb"
  load_balancer_type = "application"
  subnets            = ["subnet-052cdd25b746050e9", "subnet-0939a1c25b1c0492c", "subnet-0e6fa14ea84ea8e2e"]
  security_groups    = [aws_security_group.elb_security_group.id]
}

# Create Target Group for Blue deployment
resource "aws_lb_target_group" "blue" {
  name        = "${var.application_name}-tg-blue"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/api/dummy-data?fields=firstName,lastName,email&count=1"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Create Target Group for Green deployment
resource "aws_lb_target_group" "green" {
  name        = "${var.application_name}-tg-green"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.default.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/api/dummy-data?fields=firstName,lastName,email&count=1"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Create listener rules for ALB
resource "aws_lb_listener" "lb_listener_blue" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.certificate.arn
  default_action {
    target_group_arn = aws_lb_target_group.blue.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "listener_port_443" {
  listener_arn = aws_lb_listener.lb_listener_blue.arn
  priority     = 100
  action {
    type = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn              = aws_cognito_user_pool.user_pool.arn
      user_pool_client_id        = aws_cognito_user_pool_client.user_pool_client.id
      user_pool_domain           = aws_cognito_user_pool_domain.user_pool_domain.domain
      on_unauthenticated_request = "authenticate"
      session_cookie_name        = "generate-api-session-cookie"
      session_timeout            = 604800
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_listener" "lb_listener_green" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.green.arn
    type             = "forward"
  }
}

# Create security group for ELB
resource "aws_security_group" "elb_security_group" {
  name        = "${var.application_name}-elb-security-group"
  description = "Security group for ELB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
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


####################################AWS ECS

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

# Create ECS cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.application_name}-cluster"
}

# Create ECS service
resource "aws_ecs_service" "service" {
  name            = "${var.application_name}-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = ["subnet-052cdd25b746050e9", "subnet-0939a1c25b1c0492c", "subnet-0e6fa14ea84ea8e2e"]
    security_groups  = [aws_security_group.ecs_security_group.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.application_name
    container_port   = 80
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

####################################AWS CodeDeploy

# Create CodeDeploy application
resource "aws_codedeploy_app" "example" {
  compute_platform = "ECS"
  name             = "${var.application_name}-codedeploy-app"
}

# Create CodeDeploy deployment group
resource "aws_codedeploy_deployment_group" "example" {
  app_name               = aws_codedeploy_app.example.name
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
  deployment_group_name  = "${var.application_name}-codedeploy-deployment-group"
  service_role_arn       = aws_iam_role.codedeploy_service_role.arn

  ecs_service {
    service_name = aws_ecs_service.service.name
    cluster_name = aws_ecs_cluster.ecs_cluster.name
  }

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      termination_wait_time_in_minutes = 5
      action                           = "TERMINATE"
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.lb_listener_blue.arn]
      }

      target_group {
        name = aws_lb_target_group.blue.name
      }

      target_group {
        name = aws_lb_target_group.green.name
      }
    }
  }
}

# Create IAM role for CodeDeploy service
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${var.application_name}-codedeploy-service-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach policies to the CodeDeploy service role
resource "aws_iam_role_policy_attachment" "codedeploy_service_policy_attachment" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

####################################AWS S3

resource "aws_s3_bucket" "s3_bucket" {
  bucket = "${var.application_name}-bucket"
  acl    = "private"
}

resource "aws_s3_bucket_object" "appspec_object" {
  bucket = aws_s3_bucket.s3_bucket.id
  key    = "appspec.json"
  content = jsonencode({
    "version" : 0,
    "Resources" : [
      {
        "TargetService" : {
          "Type" : "AWS::ECS::Service",
          "Properties" : {
            "TaskDefinition" : "${aws_ecs_task_definition.task_definition.arn}",
            "LoadBalancerInfo" : {
              "ContainerName" : "generate-api",
              "ContainerPort" : 80
            }
          }
        }
      }
    ]
  })
  content_type = "application/json"
}

####################################AWS Cognito

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                                 = "${var.application_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.user_pool.id
  generate_secret                      = true
  callback_urls                        = ["https://akarsh.cloud/oauth2/idpresponse"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["aws.cognito.signin.user.admin"]
  supported_identity_providers         = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "auth-akarsh-cloud"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

####################################AWS ACM 

resource "aws_acm_certificate" "certificate" {
  domain_name       = "akarsh.cloud"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "validation" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = ["${aws_route53_record.validation_record.fqdn}"]
}

####################################AWS Route53

resource "aws_route53_record" "validation_record" {
  name    = element(aws_acm_certificate.certificate.domain_validation_options[*].resource_record_name, 0)
  type    = element(aws_acm_certificate.certificate.domain_validation_options[*].resource_record_type, 0)
  zone_id = data.aws_route53_zone.hosted_zone.id # Replace with your Route53 zone ID

  records = [element(aws_acm_certificate.certificate.domain_validation_options[*].resource_record_value, 0)]
  ttl     = 300
}

resource "aws_route53_record" "redirect" {
  zone_id = data.aws_route53_zone.hosted_zone.id # Replace with your Route 53 hosted zone ID
  name    = "akarsh.cloud"                       # Replace with your desired domain/subdomain
  type    = "A"

  alias {
    name                   = aws_lb.lb.dns_name
    zone_id                = aws_lb.lb.zone_id
    evaluate_target_health = false
  }
}

data "aws_route53_zone" "hosted_zone" {
  name = "akarsh.cloud"
}


####################################AWS WAF

resource "aws_wafv2_web_acl" "web_acl" {
  name        = "${var.application_name}-web-acl"
  description = "${var.application_name}-web-acl for rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate_limit"
    priority = 1

    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }

    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "WAFRateLimit"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WAFRateLimit"
    sampled_requests_enabled   = false
  }
}

resource "aws_wafv2_web_acl_association" "web_acl_association_my_lb" {
  resource_arn = aws_lb.lb.arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}
