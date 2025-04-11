# Target Groups
resource "aws_lb_target_group" "dashboard" {
  name                 = "${var.app_name}-dashboard-${var.environment}"
  port                 = 8501
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "backend_api" {
  name                 = "${var.app_name}-api-${var.environment}"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 30
    path                = "/docs"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "emqx_dashboard" {
  name                 = "${var.app_name}-emqx-dash-${var.environment}"
  port                 = 18083
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "emqx_mqtt" {
  name                 = "${var.app_name}-emqx-mqtt-${var.environment}"
  port                 = 1883
  protocol             = "TCP"
  vpc_id               = module.vpc.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 30
    port                = "18083" # Use the dashboard port for health check
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200"
  }

  tags = local.common_tags
}

# Create a Network Load Balancer for MQTT
resource "aws_lb" "mqtt" {
  name               = "${var.app_name}-nlb-${var.environment}"
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "prod" ? true : false

  tags = local.common_tags
}

# HTTP Listeners
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listeners
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No service specified"
      status_code  = "404"
    }
  }
}

# Dashboard HTTPS listener rule
resource "aws_lb_listener_rule" "dashboard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }

  condition {
    host_header {
      values = ["dashboard.${var.app_domain}"]
    }
  }
}

# Backend API HTTPS listener rule
resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_api.arn
  }

  condition {
    host_header {
      values = ["api.${var.app_domain}"]
    }
  }
}

# EMQX Dashboard HTTPS listener rule
resource "aws_lb_listener_rule" "emqx_dashboard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.emqx_dashboard.arn
  }

  condition {
    host_header {
      values = ["broker.${var.app_domain}"]
    }
  }
}

# MQTT Listener (TCP)
resource "aws_lb_listener" "mqtt" {
  load_balancer_arn = aws_lb.mqtt.arn
  port              = "1883"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.emqx_mqtt.arn
  }
}

# MQTTS Listener (TLS)
resource "aws_lb_listener" "mqtts" {
  load_balancer_arn = aws_lb.mqtt.arn
  port              = "8883"
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.emqx_mqtt.arn
  }
}

# ACM Certificate for HTTPS
resource "aws_acm_certificate" "main" {
  domain_name       = var.app_domain
  validation_method = "DNS"
  
  subject_alternative_names = [
    "*.${var.app_domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# DNS Validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Route53 Records
resource "aws_route53_record" "dashboard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "dashboard.${var.app_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.app_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "broker" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "broker.${var.app_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "mqtt" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "mqtt.${var.app_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.mqtt.dns_name
    zone_id                = aws_lb.mqtt.zone_id
    evaluate_target_health = true
  }
}

data "aws_route53_zone" "main" {
  name = var.route53_zone_name
} 