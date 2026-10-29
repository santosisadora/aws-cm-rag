terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Uncomment and configure for team use (remote state + locking).
  # backend "s3" {
  #   bucket       = "my-terraform-state-bucket"
  #   key          = "bedrock-rag/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.project_name
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}
