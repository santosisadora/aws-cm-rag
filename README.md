# Bedrock RAG

Retrieval-Augmented Generation on AWS Lambda using Amazon Bedrock, with source documents stored in a private S3 bucket.

## Layout

```
├── src/bedrock_rag/        # Lambda code (deployed handler: handler.lambda_handler via shim)
├── tests/                  # Unit tests (AWS clients mocked)
└── infra/
    ├── terraform/          # Recommended: private S3 bucket + Lambda execution role
    └── cli/                # Same resources via AWS CLI, plus Lambda deploy (PowerShell)
```

## Local development

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
pytest
```

## Infrastructure

Both options create the same resources:

| Resource | Configuration |
|---|---|
| S3 bucket `<project>-docs-<account>-<region>` | All public access blocked, ACLs disabled, SSE-S3 encryption, versioning, TLS-only bucket policy |
| IAM role `<project>-lambda-exec` | Trusted by `lambda.amazonaws.com` |
| Inline policy | `s3:GetObject` on `bucket/*`; `bedrock:InvokeModel` on listed model ARNs only |
| Managed policy | `AWSLambdaBasicExecutionRole` (CloudWatch Logs) |

### Option A: Terraform (recommended)

```powershell
cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # edit as needed
terraform init
terraform plan
terraform apply
```

### Option B: AWS CLI

```powershell
.\infra\cli\create-resources.ps1 -Region us-east-1 -ProjectName bedrock-rag
```

## Deploying the Lambda function

```powershell
$env:AWS_PROFILE = "admin"
.\infra\cli\deploy-lambda.ps1               # create or update CapitalMarketsRAG
.\infra\cli\deploy-lambda.ps1 -PackageOnly  # just build dist\CapitalMarketsRAG.zip
```

The zip contains the `bedrock_rag/` package plus a root `handler.py` shim, so the Lambda handler is `handler.lambda_handler`. Re-running the script updates the code and re-applies configuration.

## Creating the API Gateway HTTP API

```powershell
$env:AWS_PROFILE = "admin"
.\infra\cli\create-api.ps1
```

This creates an HTTP API (`CapitalMarketsRAG-API`), configures the Lambda proxy integration, creates a `POST /query` route, deploys to the `prod` stage, and grants `lambda:InvokeFunction` permission.

## Before invoking Bedrock

1. **Enable model access** in the Bedrock console for each model you use (region-specific).
2. **Newer models** (e.g. Claude Haiku 5.5) can only be invoked through an *inference profile*. List the profile in `bedrock_inference_profiles` (Terraform) or `-InferenceProfileIds` (CLI) so the role gets the profile ARN plus the foundation model in every region it routes to, and set `BEDROCK_MODEL_ID` to the profile ID.

## Lambda environment variables

| Variable | Required | Default |
|---|---|---|
| `BUCKET_NAME` | yes | — |
| `BEDROCK_MODEL_ID` | no | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `BEDROCK_MAX_TOKENS` | no | `1024` |
| `RAG_MAX_CONTEXT_CHARS` | no | `20000` |

Example request payload:

```json
{ "question": "What is our refund policy?", "document_key": "policies/refunds.txt" }
```

> The role intentionally has no `s3:ListBucket`, so a missing key returns `AccessDenied` instead of `NoSuchKey`. The handler maps both to HTTP 404.
