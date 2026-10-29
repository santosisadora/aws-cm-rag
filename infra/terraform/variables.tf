variable "aws_region" {
  description = "AWS region for the bucket, role policy scoping, and Bedrock models."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names. Lowercase letters, digits, and hyphens only."
  type        = string
  default     = "bedrock-rag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 chars of lowercase letters, digits, or hyphens."
  }
}

variable "bucket_name" {
  description = "Explicit S3 bucket name. Leave null to derive '<project>-docs-<account_id>-<region>'."
  type        = string
  default     = null
}

variable "force_destroy_bucket" {
  description = "Allow `terraform destroy` to delete a non-empty bucket. Keep false outside dev."
  type        = bool
  default     = false
}

variable "bedrock_model_ids" {
  description = "Foundation model IDs invoked directly (on-demand) in aws_region, e.g. embedding models."
  type        = list(string)
  default = [
    "amazon.titan-embed-text-v2:0",
  ]
}

variable "bedrock_inference_profiles" {
  description = <<-EOT
    Cross-region inference profiles the Lambda may invoke, keyed by profile ID. The role is
    granted the profile ARN plus the foundation model in every region the profile routes to.
    Find the regions with:
      aws bedrock get-inference-profile --inference-profile-identifier <profile-id>
  EOT
  type = map(object({
    model_id = string
    regions  = list(string)
  }))
  default = {
    "us.anthropic.claude-haiku-4-5-20251001-v1:0" = {
      model_id = "anthropic.claude-haiku-4-5-20251001-v1:0"
      regions  = ["us-east-1", "us-east-2", "us-west-2"]
    }
    "us.anthropic.claude-haiku-5-5" = {
      model_id = "anthropic.claude-haiku-5-5"
      regions  = ["us-east-1", "us-east-2", "us-west-2"]
    }
  }
}

variable "additional_bedrock_resource_arns" {
  description = "Any extra Bedrock resource ARNs to allow for bedrock:InvokeModel."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
