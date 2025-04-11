provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  
  backend "s3" {
    # These will be provided via -backend-config in CI/CD
  }
}

# VPC and Network Configuration
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "${var.app_name}-vpc-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false

  # Enable VPC Flow Logs for security monitoring
  enable_flow_log = true
  flow_log_destination_type = "cloud-watch-logs"
  flow_log_destination_arn = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = local.common_tags
}

# VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name = "/aws/vpc-flow-log/${var.app_name}-${var.environment}"
  retention_in_days = 7
  tags = local.common_tags
}

# Security Groups
resource "aws_security_group" "ecs_service" {
  name        = "${var.app_name}-ecs-service-sg-${var.environment}"
  description = "Security group for ECS service"
  vpc_id      = module.vpc.vpc_id
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Dashboard service ingress rules
resource "aws_security_group_rule" "dashboard_ingress" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "ingress"
  from_port         = 8501
  to_port           = 8501
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow Dashboard web access"
}

# Backend API service ingress rules
resource "aws_security_group_rule" "backend_api_ingress" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "ingress"
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow Backend API access"
}

# EMQX service ingress rules
resource "aws_security_group_rule" "emqx_mqtt_ingress" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "ingress"
  from_port         = 1883
  to_port           = 1883
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow MQTT access"
}

resource "aws_security_group_rule" "emqx_mqtts_ingress" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "ingress"
  from_port         = 8883
  to_port           = 8883
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow MQTT TLS access"
}

resource "aws_security_group_rule" "emqx_dashboard_ingress" {
  security_group_id = aws_security_group.ecs_service.id
  type              = "ingress"
  from_port         = 18083
  to_port           = 18083
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow EMQX Dashboard access"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "dashboard" {
  name              = "/ecs/${var.app_name}-dashboard-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "backend_api" {
  name              = "/ecs/${var.app_name}-backend-api-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "emqx" {
  name              = "/ecs/${var.app_name}-emqx-${var.environment}"
  retention_in_days = 30
  tags              = local.common_tags
}

# EFS for persistent EMQX data
resource "aws_efs_file_system" "emqx_data" {
  creation_token = "${var.app_name}-emqx-data-${var.environment}"
  encrypted      = true
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = local.common_tags
}

resource "aws_efs_mount_target" "emqx_data" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.emqx_data.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.app_name}-efs-sg-${var.environment}"
  description = "Security group for EFS mount targets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow NFS traffic from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = local.common_tags
}

# SSM Parameters for secrets
resource "aws_ssm_parameter" "broker_username" {
  name      = "/${var.app_name}/${var.environment}/broker/username"
  type      = "SecureString"
  value     = "admin" # Replace with your own value or use var.broker_username
  overwrite = false
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "broker_password" {
  name      = "/${var.app_name}/${var.environment}/broker/password"
  type      = "SecureString"
  value     = "admin" # Replace with your own value or use var.broker_password
  overwrite = false
  
  tags = local.common_tags
}

# Load Balancer
resource "aws_lb" "main" {
  name               = "${var.app_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "prod" ? true : false

  access_logs {
    bucket  = aws_s3_bucket.lb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }

  tags = local.common_tags
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg-${var.environment}"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
} 