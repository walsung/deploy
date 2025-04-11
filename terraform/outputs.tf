output "dashboard_url" {
  description = "URL for the dashboard web interface"
  value       = "https://dashboard.${var.app_domain}"
}

output "api_url" {
  description = "URL for the backend API"
  value       = "https://api.${var.app_domain}"
}

output "emqx_dashboard_url" {
  description = "URL for the EMQX dashboard"
  value       = "https://broker.${var.app_domain}"
}

output "mqtt_endpoint" {
  description = "Endpoint for MQTT connections"
  value       = "mqtt.${var.app_domain}"
}

output "mqtt_port" {
  description = "Port for MQTT connections"
  value       = 1883
}

output "mqtts_port" {
  description = "Port for MQTT TLS connections"
  value       = 8883
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "dashboard_cloudwatch_log_group" {
  description = "CloudWatch log group for dashboard service"
  value       = aws_cloudwatch_log_group.dashboard.name
}

output "backend_api_cloudwatch_log_group" {
  description = "CloudWatch log group for backend API service"
  value       = aws_cloudwatch_log_group.backend_api.name
}

output "emqx_cloudwatch_log_group" {
  description = "CloudWatch log group for EMQX service"
  value       = aws_cloudwatch_log_group.emqx.name
}

output "efs_bots_data_id" {
  description = "ID of the EFS for bots data"
  value       = aws_efs_file_system.bots_data.id
}

output "efs_emqx_data_id" {
  description = "ID of the EFS for EMQX data"
  value       = aws_efs_file_system.emqx_data.id
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.main.dns_name
}

output "nlb_dns_name" {
  description = "DNS name of the network load balancer"
  value       = aws_lb.mqtt.dns_name
} 