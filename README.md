# Konnekt AWS Infrastructure
**Course:** Cloud Programming — DLBSEPCP01_E  
**Student:** Eleazar Cole-Showers | 92131419

## Architecture Overview

```
Konnekt Users (Global)
        │
        ▼
Amazon CloudFront  ←── 400+ edge locations, global low latency
   │           │
   │           │ /api/* (dynamic)
   ▼           ▼
Amazon S3    Application Load Balancer
(static)          │
                  ▼
         Auto Scaling Group
         ┌────────────────┐
         │  EC2 Instance  │
         │  EC2 Instance  │  ← scales 1–4 based on CPU
         └────────────────┘

All resources provisioned by Terraform (IaC)
```

## AWS Services Used

| Service | Purpose |
|---------|---------|
| Amazon S3 | Stores static website files (HTML/CSS/JS) |
| Amazon CloudFront | CDN — serves content from nearest edge location |
| Application Load Balancer | Distributes dynamic requests across EC2 instances |
| EC2 (t2.micro) | Backend servers running Nginx |
| Auto Scaling Group | Automatically scales EC2 instances (1–4) based on CPU |
| CloudWatch Alarms | Triggers scaling policies at 70% (out) and 30% (in) CPU |
| VPC + Subnets | Isolated network across 2 Availability Zones |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- An AWS account (free tier is sufficient)

## Setup

### 1. Configure AWS credentials
```bash
aws configure
# Enter: Access Key ID, Secret Access Key, region (us-east-1), output (json)
```

### 2. Clone this repository
```bash
git clone https://github.com/YOUR_USERNAME/konnekt-aws-infrastructure.git
cd konnekt-aws-infrastructure
```

### 3. Deploy

Using the Makefile (recommended — wraps the commands below):
```bash
make test     # Format check + validate + dry-run plan (no AWS resources touched)
make apply    # Deploy to AWS (type 'yes' to confirm)
```

Or run Terraform directly:
```bash
terraform init     # Download AWS provider
terraform plan     # Preview what will be created
terraform apply    # Deploy to AWS (type 'yes' to confirm)
```

### 4. Access your site
After apply completes, Terraform prints:
```
cloudfront_url = "https://xxxxxxxxxx.cloudfront.net"
```
Open that URL in your browser — you'll see the Konnekt welcome page.

> **Note:** CloudFront distributions take 5–10 minutes to fully deploy after `terraform apply` completes.

## Teardown (avoid AWS charges)
```bash
make destroy
# or: terraform destroy
```
This removes **all** resources created by this project.

## File Structure
```
konnekt-aws/
├── main.tf         # All AWS resource definitions
├── variables.tf    # Configurable parameters
├── outputs.tf      # Values printed after deployment
├── index.html      # Static webpage uploaded to S3
├── Makefile        # Automation: make init / plan / apply / destroy / test
└── README.md       # This file
```
