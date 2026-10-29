output "bucket_name" {
  description = "Name of the private documents bucket (set as BUCKET_NAME on the Lambda)."
  value       = aws_s3_bucket.documents.id
}

output "bucket_arn" {
  description = "ARN of the private documents bucket."
  value       = aws_s3_bucket.documents.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.lambda_exec.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role."
  value       = aws_iam_role.lambda_exec.name
}

output "allowed_bedrock_resources" {
  description = "Bedrock resource ARNs the role may invoke."
  value       = local.bedrock_model_arns
}
