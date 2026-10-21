terraform {
  required_version = ">= 1.9"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.2" }
    random  = { source = "hashicorp/random", version = "~> 3.1" }
  }

  # Partial backend — bucket, key, region, and dynamodb_table passed as
  # -backend-config flags by CI and setup script.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}
