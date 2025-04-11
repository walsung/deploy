variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "deploy-app"
}

variable "ecr_repository_prefix" {
  description = "Prefix for ECR repositories"
  type        = string
  default     = "deploy-app"
}

variable "dashboard_container_image" {
  description = "Docker image for the dashboard container"
  type        = string
  default     = null
}

variable "backend_api_container_image" {
  description = "Docker image for the backend API container"
  type        = string
  default     = null
}

variable "emqx_container_image" {
  description = "Docker image for the EMQX container"
  type        = string
  default     = "emqx:5"
}

variable "dashboard_cpu" {
  description = "CPU units for the dashboard task"
  type        = number
  default     = 256
}

variable "dashboard_memory" {
  description = "Memory for the dashboard task"
  type        = number
  default     = 512
}

variable "backend_api_cpu" {
  description = "CPU units for the backend API task"
  type        = number
  default     = 512
}

variable "backend_api_memory" {
  description = "Memory for the backend API task"
  type        = number
  default     = 1024
}

variable "emqx_cpu" {
  description = "CPU units for the EMQX task"
  type        = number
  default     = 1024
}

variable "emqx_memory" {
  description = "Memory for the EMQX task"
  type        = number
  default     = 2048
}

variable "dashboard_desired_count" {
  description = "Desired count of dashboard tasks"
  type        = number
  default     = 1
}

variable "backend_api_desired_count" {
  description = "Desired count of backend API tasks"
  type        = number
  default     = 1
}

variable "emqx_desired_count" {
  description = "Desired count of EMQX tasks"
  type        = number
  default     = 1
}

variable "broker_username" {
  description = "EMQX broker username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "broker_password" {
  description = "EMQX broker password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "app_domain" {
  description = "Domain for the application (e.g., deploy-app.example.com)"
  type        = string
  default     = "deploy-app.example.com"
}

variable "route53_zone_name" {
  description = "Name of the Route53 hosted zone (e.g., example.com)"
  type        = string
  default     = "example.com"
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "Terraform"
  }
} 