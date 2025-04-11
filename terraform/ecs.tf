# ECS Execution Role - used by the ECS agent
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-${var.environment}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  tags = local.common_tags
}

# Task Role - used by the containers
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.app_name}-${var.environment}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Access to SSM Parameters
resource "aws_iam_policy" "ssm_parameter_access" {
  name        = "${var.app_name}-${var.environment}-ssm-access"
  description = "Allow ECS task to access SSM Parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = [
          aws_ssm_parameter.broker_username.arn,
          aws_ssm_parameter.broker_password.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_ssm_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ssm_parameter_access.arn
}

# Dashboard Service
resource "aws_ecs_task_definition" "dashboard" {
  family                   = "${var.app_name}-dashboard-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.dashboard_cpu
  memory                   = var.dashboard_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "dashboard"
      image     = var.dashboard_container_image != null ? var.dashboard_container_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_prefix}-dashboard:latest"
      essential = true
      
      environment = [
        { name = "AUTH_SYSTEM_ENABLED", value = "False" },
        { name = "BACKEND_API_HOST", value = "backend-api.${var.app_name}.${var.environment}.local" },
        { name = "BACKEND_API_PORT", value = "8000" },
        { name = "BACKEND_API_USERNAME", value = "admin" },
        { name = "BACKEND_API_PASSWORD", value = "admin" }
      ]
      
      mountPoints = []
      
      portMappings = [
        {
          containerPort = 8501
          hostPort      = 8501
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dashboard.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "dashboard"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "dashboard" {
  name                               = "dashboard"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.dashboard.arn
  desired_count                      = var.dashboard_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60
  enable_execute_command             = true
  
  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dashboard.arn
    container_name   = "dashboard"
    container_port   = 8501
  }

  service_registries {
    registry_arn = aws_service_discovery_service.dashboard.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.common_tags
}

# Backend API Service
resource "aws_ecs_task_definition" "backend_api" {
  family                   = "${var.app_name}-backend-api-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_api_cpu
  memory                   = var.backend_api_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend-api"
      image     = var.backend_api_container_image != null ? var.backend_api_container_image : "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_prefix}-backend-api:latest"
      essential = true
      
      environment = [
        { name = "BROKER_HOST", value = "emqx.${var.app_name}.${var.environment}.local" },
        { name = "BROKER_PORT", value = "1883" },
        { name = "USERNAME", value = "admin" },
        { name = "PASSWORD", value = "admin" }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "bots-volume"
          containerPath = "/backend-api/bots"
          readOnly      = false
        }
      ]
      
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend-api"
        }
      }
    }
  ])

  volume {
    name = "bots-volume"
    
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.bots_data.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.bots_data.id
        iam             = "ENABLED"
      }
    }
  }

  tags = local.common_tags
}

resource "aws_efs_file_system" "bots_data" {
  creation_token = "${var.app_name}-bots-data-${var.environment}"
  encrypted      = true
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = local.common_tags
}

resource "aws_efs_access_point" "bots_data" {
  file_system_id = aws_efs_file_system.bots_data.id
  
  posix_user {
    gid = 1000
    uid = 1000
  }
  
  root_directory {
    path = "/bots"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = local.common_tags
}

resource "aws_efs_mount_target" "bots_data" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.bots_data.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_ecs_service" "backend_api" {
  name                               = "backend-api"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.backend_api.arn
  desired_count                      = var.backend_api_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 60
  enable_execute_command             = true
  
  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_api.arn
    container_name   = "backend-api"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend_api.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.common_tags
}

# EMQX Service
resource "aws_ecs_task_definition" "emqx" {
  family                   = "${var.app_name}-emqx-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.emqx_cpu
  memory                   = var.emqx_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "emqx"
      image     = var.emqx_container_image
      essential = true
      
      environment = [
        { name = "EMQX_NAME", value = "emqx" },
        { name = "EMQX_HOST", value = "node1.emqx.${var.app_name}.${var.environment}.local" },
        { name = "EMQX_CLUSTER__DISCOVERY_STRATEGY", value = "static" },
        { name = "EMQX_CLUSTER__STATIC__SEEDS", value = "[emqx@node1.emqx.${var.app_name}.${var.environment}.local]" },
        { name = "EMQX_LOADED_PLUGINS", value = "emqx_recon,emqx_retainer,emqx_management,emqx_dashboard" }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "emqx-data"
          containerPath = "/opt/emqx/data"
          readOnly      = false
        },
        {
          sourceVolume  = "emqx-log"
          containerPath = "/opt/emqx/log"
          readOnly      = false
        },
        {
          sourceVolume  = "emqx-etc"
          containerPath = "/opt/emqx/etc"
          readOnly      = false
        }
      ]
      
      portMappings = [
        {
          containerPort = 1883
          hostPort      = 1883
          protocol      = "tcp"
        },
        {
          containerPort = 8883
          hostPort      = 8883
          protocol      = "tcp"
        },
        {
          containerPort = 8083
          hostPort      = 8083
          protocol      = "tcp"
        },
        {
          containerPort = 8084
          hostPort      = 8084
          protocol      = "tcp"
        },
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        },
        {
          containerPort = 18083
          hostPort      = 18083
          protocol      = "tcp"
        },
        {
          containerPort = 61613
          hostPort      = 61613
          protocol      = "tcp"
        }
      ]
      
      healthCheck = {
        command     = ["CMD", "/opt/emqx/bin/emqx_ctl", "status"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.emqx.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "emqx"
        }
      }
    }
  ])

  volume {
    name = "emqx-data"
    
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.emqx_data.id
      transit_encryption = "ENABLED"
    }
  }

  volume {
    name = "emqx-log"
    
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.emqx_data.id
      transit_encryption = "ENABLED"
      root_directory     = "/logs"
    }
  }

  volume {
    name = "emqx-etc"
    
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.emqx_data.id
      transit_encryption = "ENABLED"
      root_directory     = "/etc"
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "emqx" {
  name                               = "emqx"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.emqx.arn
  desired_count                      = var.emqx_desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = 90
  enable_execute_command             = true
  
  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.emqx_dashboard.arn
    container_name   = "emqx"
    container_port   = 18083
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.emqx_mqtt.arn
    container_name   = "emqx"
    container_port   = 1883
  }

  service_registries {
    registry_arn = aws_service_discovery_service.emqx.arn
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.common_tags
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.app_name}.${var.environment}.local"
  description = "Service discovery namespace for ${var.app_name} in ${var.environment}"
  vpc         = module.vpc.vpc_id
  
  tags = local.common_tags
}

resource "aws_service_discovery_service" "dashboard" {
  name = "dashboard"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "backend_api" {
  name = "backend-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "emqx" {
  name = "emqx"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
} 