
# Konnekt AWS Infrastructure — automation
# Course: Cloud Programming DLBSEPCP01_E

.PHONY: init fmt validate plan apply destroy test clean

init:
	terraform init

fmt:
	terraform fmt -check -diff -recursive

validate: init
	terraform validate

# Full pre-submission check: formatting + syntax + dry-run plan
# Does NOT touch real AWS resources.
test: fmt validate
	terraform plan

plan: init
	terraform plan

apply: init
	terraform apply

destroy:
	terraform destroy

# Remove local Terraform working files (safe — does not touch remote AWS state)
clean:
	rm -rf .terraform
	rm -f .terraform.tfstate.lock.info terraform.tfstate.backup
