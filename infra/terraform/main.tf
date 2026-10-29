data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  bucket_name = coalesce(var.bucket_name, "${var.project_name}-docs-${local.account_id}-${var.aws_region}")

  # Cross-region inference profiles need both the profile ARN and the foundation-model
  # ARN in every region the profile can route requests to.
  bedrock_profile_arns = flatten([
    for profile_id, profile in var.bedrock_inference_profiles : concat(
      ["arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${profile_id}"],
      [for region in profile.regions : "arn:${local.partition}:bedrock:${region}::foundation-model/${profile.model_id}"],
    )
  ])

  bedrock_model_arns = distinct(concat(
    [for id in var.bedrock_model_ids : "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/${id}"],
    local.bedrock_profile_arns,
    var.additional_bedrock_resource_arns,
  ))
}

# -----------------------------------------------------------------------------
# Private S3 bucket for RAG source documents
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "documents" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Disables ACLs entirely; access is governed only by IAM and bucket policy.
resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "bucket_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.documents.arn,
      "${aws_s3_bucket.documents.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = data.aws_iam_policy_document.bucket_tls_only.json

  # Ensure the public access block is in place before any policy is attached.
  depends_on = [aws_s3_bucket_public_access_block.documents]
}

# -----------------------------------------------------------------------------
# Lambda execution role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  description        = "Execution role for the ${var.project_name} RAG Lambda function"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "ReadRagDocuments"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
  }

  statement {
    sid       = "InvokeBedrockModels"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = local.bedrock_model_arns
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${var.project_name}-s3-bedrock"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# CloudWatch Logs permissions so the function can write its logs.
resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
