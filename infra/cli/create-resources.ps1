<#
.SYNOPSIS
    AWS CLI equivalent of infra/terraform: creates a private S3 bucket and a Lambda
    execution role with s3:GetObject and bedrock:InvokeModel permissions.

.DESCRIPTION
    Safe to re-run: existing bucket/role are detected and their settings re-applied.
    Requires AWS CLI v2 with credentials configured (aws configure / aws sso login).

.EXAMPLE
    .\create-resources.ps1 -Region us-east-1 -ProjectName bedrock-rag
#>
[CmdletBinding()]
param(
    [string]   $Region      = "us-east-1",
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$')]
    [string]   $ProjectName = "bedrock-rag",
    [string]   $BucketName,
    # On-demand foundation models (e.g. embeddings) invoked directly in $Region.
    [string[]] $ModelIds    = @(
        "amazon.titan-embed-text-v2:0"
    ),
    # Cross-region inference profiles (required by newer models such as Claude Haiku 4.5 and 5.5).
    [string[]] $InferenceProfileIds = @(
        "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        "us.anthropic.claude-haiku-5-5"
    )
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Invoke-Aws {
    # Runs the AWS CLI and throws on a non-zero exit code.
    $output = & aws @args --region $Region
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): aws $($args -join ' ')" }
    return $output
}

function Test-AwsCommand {
    # Returns $true if the AWS CLI command succeeds (used for existence checks).
    $ErrorActionPreference = "Continue"
    & aws @args --region $Region 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Write-JsonFile([string] $Name, $Object) {
    # UTF-8 without BOM; the AWS CLI reads these via file://
    $path = Join-Path $workDir $Name
    [System.IO.File]::WriteAllText($path, ($Object | ConvertTo-Json -Depth 10))
    return "file://$path"
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "bedrock-rag-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $workDir | Out-Null

try {
    $accountId = Invoke-Aws sts get-caller-identity --query Account --output text
    $partition = (Invoke-Aws sts get-caller-identity --query Arn --output text).Split(":")[1]
    if (-not $BucketName) { $BucketName = "$ProjectName-docs-$accountId-$Region" }
    $bucketArn = "arn:${partition}:s3:::$BucketName"
    $roleName  = "$ProjectName-lambda-exec"

    Write-Host "Account: $accountId  Region: $Region  Bucket: $BucketName  Role: $roleName" -ForegroundColor Cyan

    # ---------------------------------------------------------------- S3 bucket
    if (Test-AwsCommand s3api head-bucket --bucket $BucketName) {
        Write-Host "Bucket already exists; re-applying settings."
    } else {
        Write-Host "Creating bucket..."
        if ($Region -eq "us-east-1") {
            # us-east-1 rejects an explicit LocationConstraint.
            Invoke-Aws s3api create-bucket --bucket $BucketName | Out-Null
        } else {
            Invoke-Aws s3api create-bucket --bucket $BucketName `
                --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
        }
        Invoke-Aws s3api wait bucket-exists --bucket $BucketName | Out-Null
    }

    Invoke-Aws s3api put-public-access-block --bucket $BucketName `
        --public-access-block-configuration `
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

    $ownership = Write-JsonFile "ownership.json" @{ Rules = @(@{ ObjectOwnership = "BucketOwnerEnforced" }) }
    Invoke-Aws s3api put-bucket-ownership-controls --bucket $BucketName --ownership-controls $ownership | Out-Null

    $encryption = Write-JsonFile "encryption.json" @{
        Rules = @(@{ ApplyServerSideEncryptionByDefault = @{ SSEAlgorithm = "AES256" } })
    }
    Invoke-Aws s3api put-bucket-encryption --bucket $BucketName `
        --server-side-encryption-configuration $encryption | Out-Null

    Invoke-Aws s3api put-bucket-versioning --bucket $BucketName `
        --versioning-configuration "Status=Enabled" | Out-Null

    $bucketPolicy = Write-JsonFile "bucket-policy.json" @{
        Version   = "2012-10-17"
        Statement = @(@{
            Sid       = "DenyInsecureTransport"
            Effect    = "Deny"
            Principal = "*"
            Action    = "s3:*"
            Resource  = @($bucketArn, "$bucketArn/*")
            Condition = @{ Bool = @{ "aws:SecureTransport" = "false" } }
        })
    }
    Invoke-Aws s3api put-bucket-policy --bucket $BucketName --policy $bucketPolicy | Out-Null

    # ---------------------------------------------------------------- IAM role
    $trustPolicy = Write-JsonFile "trust-policy.json" @{
        Version   = "2012-10-17"
        Statement = @(@{
            Effect    = "Allow"
            Principal = @{ Service = "lambda.amazonaws.com" }
            Action    = "sts:AssumeRole"
        })
    }

    if (Test-AwsCommand iam get-role --role-name $roleName) {
        Write-Host "Role already exists; updating trust and permissions."
        Invoke-Aws iam update-assume-role-policy --role-name $roleName --policy-document $trustPolicy | Out-Null
    } else {
        Write-Host "Creating IAM role..."
        Invoke-Aws iam create-role --role-name $roleName `
            --description "Execution role for the $ProjectName RAG Lambda function" `
            --assume-role-policy-document $trustPolicy | Out-Null
        Invoke-Aws iam wait role-exists --role-name $roleName | Out-Null
    }

    $modelArns = @($ModelIds | ForEach-Object { "arn:${partition}:bedrock:${Region}::foundation-model/$_" })

    # Each profile needs its own ARN plus the foundation model in every region it routes to.
    foreach ($profileId in $InferenceProfileIds) {
        $inferenceProfile = (Invoke-Aws bedrock get-inference-profile `
            --inference-profile-identifier $profileId `
            --query "{arn:inferenceProfileArn,models:models[].modelArn}" `
            --output json) -join "`n" | ConvertFrom-Json
        Write-Host "Inference profile $profileId routes to $(@($inferenceProfile.models).Count) model ARN(s)."
        $modelArns += $inferenceProfile.arn
        $modelArns += @($inferenceProfile.models)
    }
    $modelArns = @($modelArns | Select-Object -Unique)
    $permissions = Write-JsonFile "permissions.json" @{
        Version   = "2012-10-17"
        Statement = @(
            @{
                Sid      = "ReadRagDocuments"
                Effect   = "Allow"
                Action   = "s3:GetObject"
                Resource = "$bucketArn/*"
            },
            @{
                Sid      = "InvokeBedrockModels"
                Effect   = "Allow"
                Action   = "bedrock:InvokeModel"
                Resource = $modelArns
            }
        )
    }
    Invoke-Aws iam put-role-policy --role-name $roleName `
        --policy-name "$ProjectName-s3-bedrock" --policy-document $permissions | Out-Null

    # CloudWatch Logs permissions so the function can write its logs.
    Invoke-Aws iam attach-role-policy --role-name $roleName `
        --policy-arn "arn:${partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" | Out-Null

    $roleArn = Invoke-Aws iam get-role --role-name $roleName --query Role.Arn --output text

    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
    Write-Host "  bucket_name     = $BucketName"
    Write-Host "  lambda_role_arn = $roleArn"
}
finally {
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
}
