# ============================================================
# main.tf — Konnekt AWS Infrastructure
# Course: Cloud Programming DLBSEPCP01_E
# Student: Eleazar Cole-Showers | 92131419
#
# Architecture:
#   Konnekt Users → CloudFront → S3 (static)
#                             → ALB → EC2 Auto Scaling Group (dynamic)
#   All resources provisioned via Terraform (IaC)
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# DATA SOURCES
# ============================================================

# Fetch the latest Amazon Linux 2 AMI for EC2 instances
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================
# COMPONENT 1 — NETWORKING (VPC, Subnets, IGW, Route Table)
# Required for EC2 instances and the Load Balancer
# ============================================================

resource "aws_vpc" "konnekt_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "konnekt_igw" {
  vpc_id = aws_vpc.konnekt_vpc.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Two public subnets in different Availability Zones → High Availability
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.konnekt_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet-${count.index + 1}"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.konnekt_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.konnekt_igw.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# COMPONENT 2 — AMAZON S3 (Static Content Storage)
# Stores Konnekt's HTML/CSS/JS files
# CloudFront reads from this bucket (not public directly)
# ============================================================

resource "aws_s3_bucket" "konnekt_static" {
  bucket = "${var.project_name}-static-site-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-static"
    Project = var.project_name
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Block all public access — CloudFront will access it via OAC instead
resource "aws_s3_bucket_public_access_block" "konnekt_static" {
  bucket = aws_s3_bucket.konnekt_static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the hello-world HTML file to S3
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.konnekt_static.id
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")
}

# ============================================================
# COMPONENT 3 — AMAZON CLOUDFRONT (CDN — Global Low Latency)
# Serves static content from S3 via 400+ edge locations
# Forwards dynamic requests to the ALB
# ============================================================

# Origin Access Control: lets CloudFront access S3 privately
resource "aws_cloudfront_origin_access_control" "konnekt_oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for Konnekt S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "konnekt_cdn" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "Konnekt CDN — global delivery for static and dynamic content"

  # Origin 1: S3 for static files
  origin {
    domain_name              = aws_s3_bucket.konnekt_static.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.konnekt_static.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.konnekt_oac.id
  }

  # Origin 2: Application Load Balancer for dynamic requests
  origin {
    domain_name = aws_lb.konnekt_alb.dns_name
    origin_id   = "ALB-konnekt"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior: serve static files from S3
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.konnekt_static.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # /api/* behavior: forward dynamic requests to the ALB
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALB-konnekt"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name    = "${var.project_name}-cdn"
    Project = var.project_name
  }

  depends_on = [aws_lb.konnekt_alb]
}

# Allow CloudFront to read from S3 via OAC
resource "aws_s3_bucket_policy" "cloudfront_access" {
  bucket = aws_s3_bucket.konnekt_static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.konnekt_static.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.konnekt_cdn.arn
          }
        }
      }
    ]
  })
}

# ============================================================
# SECURITY GROUPS
# Controls which traffic is allowed in/out of each component
# ============================================================

# ALB security group: allow HTTP from the internet
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP inbound to the Application Load Balancer"
  vpc_id      = aws_vpc.konnekt_vpc.id

  ingress {
    description = "HTTP from internet"
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

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

# EC2 security group: only allow traffic from the ALB
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow HTTP inbound only from the ALB"
  vpc_id      = aws_vpc.konnekt_vpc.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}

# ============================================================
# COMPONENT 4A — APPLICATION LOAD BALANCER
# Distributes dynamic traffic across EC2 instances
# ============================================================

resource "aws_lb" "konnekt_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "konnekt_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.konnekt_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name    = "${var.project_name}-tg"
    Project = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.konnekt_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.konnekt_tg.arn
  }
}

# ============================================================
# COMPONENT 4B — EC2 LAUNCH TEMPLATE
# Defines the EC2 instance configuration used by Auto Scaling
# ============================================================

resource "aws_launch_template" "konnekt_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.ec2_instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  # User data: installs Nginx and serves a simple page on launch
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install -y nginx1
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Konnekt Backend — Instance $(hostname)</h1>" > /usr/share/nginx/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-ec2"
      Project = var.project_name
    }
  }
}

# ============================================================
# COMPONENT 4C — AUTO SCALING GROUP
# Automatically adds/removes EC2 instances based on traffic
# Satisfies the autoscaling requirement from Phase 1
# ============================================================

resource "aws_autoscaling_group" "konnekt_asg" {
  name                = "${var.project_name}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.konnekt_tg.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.konnekt_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# Auto Scaling Policy: scale OUT when CPU > 70%
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.konnekt_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU exceeds 70% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.konnekt_asg.name
  }
}

# Auto Scaling Policy: scale IN when CPU < 30%
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.konnekt_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when average CPU drops below 30% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.konnekt_asg.name
  }
}
