<#
.SYNOPSIS
    Creates an Amazon API Gateway HTTP API (v2) and integrates it with CapitalMarketsRAG.

.DESCRIPTION
    1. Locates or creates an HTTP API named CapitalMarketsRAG-API.
    2. Configures an AWS_PROXY integration targeting the CapitalMarketsRAG Lambda.
    3. Configures a POST /query route targeting the Lambda integration.
    4. Creates or updates the stage named 'prod' with auto-deploy enabled.
    5. Grants API Gateway permissions (lambda:InvokeFunction) to invoke the function.
    6. Outputs the full POST endpoint URL.

.EXAMPLE
    $env:AWS_PROFILE = "admin"
    .\infra\cli\create-api.ps1
#>
[CmdletBinding()]
param(
    [string] $ApiName      = "CapitalMarketsRAG-API",
    [string] $FunctionName = "CapitalMarketsRAG",
    [string] $Region       = "us-east-1",
    [string] $StageName    = "prod",
    [string] $RouteKey     = "POST /query"
)

$ErrorActionPreference = "Stop"
$env:AWS_PAGER = ""

function Invoke-Aws {
    $output = & aws @args --region $Region
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): aws $($args -join ' ')" }
    return $output
}

function Test-AwsCommand {
    $ErrorActionPreference = "Continue"
    & aws @args --region $Region 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Host "Configuring API Gateway HTTP API for $FunctionName in $Region..." -ForegroundColor Cyan

# 1. Resolve Account ID, Partition, and Lambda Function ARN
$identityJson = (Invoke-Aws sts get-caller-identity --output json) -join "`n" | ConvertFrom-Json
$accountId    = $identityJson.Account
$partition    = $identityJson.Arn.Split(":")[1]

if (-not (Test-AwsCommand lambda get-function --function-name $FunctionName)) {
    throw "Lambda function '$FunctionName' was not found in $Region. Deploy it first using deploy-lambda.ps1."
}

$functionArn = Invoke-Aws lambda get-function-configuration `
    --function-name $FunctionName `
    --query FunctionArn `
    --output text

Write-Host "Target Lambda ARN: $functionArn"

# 2. Get or Create HTTP API
$existingApiId = (Invoke-Aws apigatewayv2 get-apis `
    --query "Items[?Name=='$ApiName'].ApiId | [0]" `
    --output text)

if ($existingApiId -and $existingApiId -ne "None") {
    $apiId = $existingApiId
    Write-Host "Found existing HTTP API: $ApiName (ID: $apiId)"
    Invoke-Aws apigatewayv2 update-api `
        --api-id $apiId `
        --cors-configuration "AllowOrigins='*',AllowMethods='POST,OPTIONS',AllowHeaders='Content-Type,Authorization',MaxAge=3600" | Out-Null
} else {
    Write-Host "Creating HTTP API '$ApiName'..."
    $apiJson = (Invoke-Aws apigatewayv2 create-api `
        --name $ApiName `
        --protocol-type HTTP `
        --cors-configuration "AllowOrigins='*',AllowMethods='POST,OPTIONS',AllowHeaders='Content-Type,Authorization',MaxAge=3600" `
        --output json) -join "`n" | ConvertFrom-Json
    $apiId = $apiJson.ApiId
    Write-Host "Created HTTP API with ID: $apiId" -ForegroundColor Green
}

# 3. Create or Update Integration with Lambda
$existingIntegrationId = (Invoke-Aws apigatewayv2 get-integrations `
    --api-id $apiId `
    --query "Items[?IntegrationUri=='$functionArn'].IntegrationId | [0]" `
    --output text)

if ($existingIntegrationId -and $existingIntegrationId -ne "None") {
    $integrationId = $existingIntegrationId
    Write-Host "Using existing Lambda integration (ID: $integrationId)"
} else {
    Write-Host "Creating Lambda proxy integration..."
    $integrationJson = (Invoke-Aws apigatewayv2 create-integration `
        --api-id $apiId `
        --integration-type AWS_PROXY `
        --integration-uri $functionArn `
        --payload-format-version "2.0" `
        --output json) -join "`n" | ConvertFrom-Json
    $integrationId = $integrationJson.IntegrationId
    Write-Host "Created integration with ID: $integrationId" -ForegroundColor Green
}

# 4. Create or Update Route (POST /query)
$existingRouteId = (Invoke-Aws apigatewayv2 get-routes `
    --api-id $apiId `
    --query "Items[?RouteKey=='$RouteKey'].RouteId | [0]" `
    --output text)

$target = "integrations/$integrationId"

if ($existingRouteId -and $existingRouteId -ne "None") {
    Write-Host "Updating route '$RouteKey' to target integration..."
    Invoke-Aws apigatewayv2 update-route `
        --api-id $apiId `
        --route-id $existingRouteId `
        --target $target | Out-Null
    $routeId = $existingRouteId
} else {
    Write-Host "Creating route '$RouteKey'..."
    $routeJson = (Invoke-Aws apigatewayv2 create-route `
        --api-id $apiId `
        --route-key $RouteKey `
        --target $target `
        --output json) -join "`n" | ConvertFrom-Json
    $routeId = $routeJson.RouteId
    Write-Host "Created route with ID: $routeId" -ForegroundColor Green
}

# 5. Create or Update Stage ('prod') with Auto-Deploy
$stageExists = Test-AwsCommand apigatewayv2 get-stage `
    --api-id $apiId `
    --stage-name $StageName

if ($stageExists) {
    Write-Host "Updating stage '$StageName' with auto-deploy enabled..."
    Invoke-Aws apigatewayv2 update-stage `
        --api-id $apiId `
        --stage-name $StageName `
        --auto-deploy | Out-Null
} else {
    Write-Host "Creating stage '$StageName' with auto-deploy enabled..."
    Invoke-Aws apigatewayv2 create-stage `
        --api-id $apiId `
        --stage-name $StageName `
        --auto-deploy | Out-Null
}

# 6. Grant API Gateway Permission to Invoke Lambda
$statementId = "apigateway-$apiId-$StageName"
$sourceArn   = "arn:${partition}:execute-api:${Region}:${accountId}:${apiId}/*"

$hasPermission = $false
if (Test-AwsCommand lambda get-policy --function-name $FunctionName) {
    $policyJsonRaw = (Invoke-Aws lambda get-policy --function-name $FunctionName --query Policy --output text)
    if ($policyJsonRaw -match [regex]::Escape($statementId)) {
        $hasPermission = $true
    }
}

if ($hasPermission) {
    Write-Host "Lambda invocation permission ($statementId) is already configured."
} else {
    Write-Host "Adding Lambda invoke permission for API Gateway..."
    Invoke-Aws lambda add-permission `
        --function-name $FunctionName `
        --statement-id $statementId `
        --action lambda:InvokeFunction `
        --principal apigateway.amazonaws.com `
        --source-arn $sourceArn | Out-Null
    Write-Host "Granted lambda:InvokeFunction permission." -ForegroundColor Green
}

# 7. Print Final Endpoint URL
$endpointBase = "https://$apiId.execute-api.$Region.amazonaws.com/$StageName"
$pathPart     = $RouteKey.Split(" ")[1].TrimStart("/")
$fullEndpoint = "$endpointBase/$pathPart"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "API Gateway deployed successfully!" -ForegroundColor Green
Write-Host "  API ID       : $apiId"
Write-Host "  Stage        : $StageName"
Write-Host "  Method/Route : $RouteKey"
Write-Host "  Endpoint URL : $fullEndpoint" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Test invoking with curl or Invoke-RestMethod:" -ForegroundColor Cyan
Write-Host "curl -X POST `"$fullEndpoint`" -H `"Content-Type: application/json`" -d '@payload.json'"
Write-Host "Invoke-RestMethod -Method Post -Uri `"$fullEndpoint`" -ContentType 'application/json' -Infile payload.json"
