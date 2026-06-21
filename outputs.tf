# ============================================================
# outputs.tf — Konnekt AWS Infrastructure
# Course: Cloud Programming DLBSEPCP01_E
# ============================================================
# After running `terraform apply`, these values are printed
# to the terminal so you can immediately test the deployment.

output "cloudfront_url" {
  description = "The public CloudFront URL — open this in your browser to see Konnekt"
  value       = "https://${aws_cloudfront_distribution.konnekt_cdn.domain_name}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing Konnekt's static files"
  value       = aws_s3_bucket.konnekt_static.bucket
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (for direct backend testing)"
  value       = aws_lb.konnekt_alb.dns_name
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group managing EC2 instances"
  value       = aws_autoscaling_group.konnekt_asg.name
}

output "vpc_id" {
  description = "ID of the VPC created for this project"
  value       = aws_vpc.konnekt_vpc.id
}
