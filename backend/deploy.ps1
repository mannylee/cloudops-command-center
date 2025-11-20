# AWS Health Dashboard Deployment Script - PowerShell Version
# Requires: PowerShell 5.1+, AWS CLI, Terraform

#Requires -Version 5.1

# Stop on errors
$ErrorActionPreference = "Stop"

# Color output functions
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Global variables
$script:SelectedAwsProfile = ""
$script:RedeployMode = $false
$script:SkipBedrockValidation = $false
$script:UsingExistingConfig = $false

# Function to show help
function Show-Help {
    Write-Host "AWS Health Dashboard Deployment Script"
    Write-Host ""
    Write-Host "Usage: .\deploy.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  deploy      Deploy complete infrastructure (default)"
    Write-Host "  destroy     Destroy infrastructure with backend option"
    Write-Host "  configure   Configure deployment settings only"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Redeploy              Redeploy using existing configuration without prompts"
    Write-Host "  -SkipBedrockValidation Skip Bedrock model access validation (advanced users only)"
    Write-Host "  -Help                  Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\deploy.ps1                          Interactive deployment with full validation"
    Write-Host "  .\deploy.ps1 -Redeploy                Redeploy with existing config and validation"
    Write-Host "  .\deploy.ps1 destroy                  Destroy infrastructure"
    Write-Host "  .\deploy.ps1 configure                Configure deployment settings only"
    Write-Host "  .\deploy.ps1 -SkipBedrockValidation   Deploy without checking Bedrock model access"
    Write-Host ""
    Write-Host "Note: Skipping Bedrock validation may result in runtime errors if models are not accessible."
}

# Function to clean environment variables
function Clear-EnvVars {
    Remove-Item Env:\TF_BACKEND_BUCKET -ErrorAction SilentlyContinue
    Remove-Item Env:\TF_BACKEND_TABLE -ErrorAction SilentlyContinue
    Remove-Item Env:\AWS_PROFILE -ErrorAction SilentlyContinue
}

# Function to setup AWS profile
function Setup-AwsProfile {
    $tfvarsFile = "environment\terraform.tfvars"
    
    if ((Test-Path $tfvarsFile) -and ($script:RedeployMode -or $script:UsingExistingConfig)) {
        $content = Get-Content $tfvarsFile -Raw
        if ($content -match 'aws_profile\s*=\s*"([^"]+)"') {
            $script:SelectedAwsProfile = $matches[1]
            $env:AWS_PROFILE = $script:SelectedAwsProfile
            Write-Status "Using AWS profile from existing config: $script:SelectedAwsProfile"
        } else {
            Write-ErrorMsg "AWS profile not found in configuration"
            exit 1
        }
    } else {
        # Interactive mode
        try {
            $profiles = aws configure list-profiles 2>$null
            if (-not $profiles) {
                $profiles = @("default")
            }
        } catch {
            $profiles = @("default")
        }
        
        if ($profiles.Count -eq 1) {
            $script:SelectedAwsProfile = $profiles[0]
            Write-Status "Using AWS profile: $script:SelectedAwsProfile"
        } else {
            Write-Status "Available AWS profiles:"
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                Write-Host "  $($i+1)) $($profiles[$i])"
            }
            
            do {
                $choice = Read-Host "Select profile (1-$($profiles.Count))"
                $choiceNum = [int]$choice
            } while ($choiceNum -lt 1 -or $choiceNum -gt $profiles.Count)
            
            $script:SelectedAwsProfile = $profiles[$choiceNum - 1]
            Write-Status "Selected AWS profile: $script:SelectedAwsProfile"
        }
        
        $env:AWS_PROFILE = $script:SelectedAwsProfile
    }
    
    # Test credentials
    try {
        aws sts get-caller-identity | Out-Null
        Write-Success "AWS credentials validated for profile: $script:SelectedAwsProfile"
    } catch {
        Write-ErrorMsg "AWS credentials not working for profile: $script:SelectedAwsProfile"
        Write-ErrorMsg "Please configure AWS CLI properly"
        exit 1
    }
}

# Function to check for naming configuration changes
function Test-NamingChanges {
    param(
        [string]$TfvarsFile,
        [string]$NewPrefix,
        [string]$NewSuffix,
        [string]$NewRandom
    )
    
    if (-not (Test-Path $TfvarsFile)) {
        return $true
    }
    
    $content = Get-Content $TfvarsFile -Raw
    
    # Extract current naming configuration
    $currentPrefix = ""
    $currentSuffix = ""
    $currentRandom = "false"
    
    if ($content -match 'naming_convention\s*=\s*\{[^}]*prefix\s*=\s*"([^"]*)"') {
        $currentPrefix = $matches[1]
    }
    if ($content -match 'naming_convention\s*=\s*\{[^}]*suffix\s*=\s*"([^"]*)"') {
        $currentSuffix = $matches[1]
    }
    if ($content -match 'naming_convention\s*=\s*\{[^}]*use_random_suffix\s*=\s*(true|false)') {
        $currentRandom = $matches[1]
    }
    
    if ($currentPrefix -ne $NewPrefix -or $currentSuffix -ne $NewSuffix -or $currentRandom -ne $NewRandom) {
        Write-Host ""
        Write-Warning "⚠️  NAMING CONFIGURATION CHANGE DETECTED ⚠️"
        Write-Host "=================================="
        Write-Warning "Changing resource naming will force recreation of most AWS resources!"
        Write-Host ""
        Write-Status "Current naming:"
        Write-Host "  • Prefix: '$currentPrefix'"
        Write-Host "  • Suffix: '$currentSuffix'"
        Write-Host "  • Random suffix: $currentRandom"
        Write-Host ""
        Write-Status "New naming:"
        Write-Host "  • Prefix: '$NewPrefix'"
        Write-Host "  • Suffix: '$NewSuffix'"
        Write-Host "  • Random suffix: $NewRandom"
        Write-Host ""
        Write-Warning "Resources that will be RECREATED (causing downtime):"
        Write-Host "  • Lambda functions (event-processor, events-api)"
        Write-Host "  • DynamoDB tables (all data will be lost)"
        Write-Host "  • SQS queues"
        Write-Host "  • API Gateway"
        Write-Host "  • CloudWatch Log Groups"
        Write-Host "  • IAM roles and policies"
        Write-Host ""
        Write-Warning "This will result in:"
        Write-Host "  • Temporary service downtime during recreation"
        Write-Host "  • Loss of all stored health event data"
        Write-Host "  • New API endpoints (frontend may need updates)"
        Write-Host "=================================="
        Write-Host ""
        
        $response = Read-Host "Do you want to continue with these naming changes? (y/N)"
        if ($response -notmatch '^[yY]') {
            Write-Status "Keeping existing naming configuration"
            return $false
        }
        
        Write-Host ""
        Write-Status "Proceeding with naming changes..."
    }
    
    return $true
}

# Function to validate bucket naming
function Test-BucketNaming {
    param(
        [string]$Prefix,
        [string]$Suffix,
        [string]$UseRandom
    )
    
    $baseName = "health-dashboard"
    $backendSuffix = "backend-terraform-state"
    $randomHexLength = 8
    
    $totalLength = 0
    
    if ($Prefix) {
        $totalLength += $Prefix.Length + 1
    }
    
    $totalLength += $baseName.Length + 1
    
    if ($Suffix) {
        $totalLength += $Suffix.Length + 1
    }
    
    if ($UseRandom -eq "true") {
        $totalLength += 8 + 1
    }
    
    $totalLength += $backendSuffix.Length + 1
    $totalLength += $randomHexLength
    
    if ($totalLength -gt 63) {
        Write-Host ""
        Write-ErrorMsg "⚠️  BUCKET NAME TOO LONG ⚠️"
        Write-Host "=================================="
        Write-ErrorMsg "The generated S3 bucket name will be $totalLength characters (limit: 63)"
        Write-Host ""
        Write-Status "Current naming configuration:"
        Write-Host "  • Prefix: '$Prefix' ($($Prefix.Length) chars)"
        Write-Host "  • Base: '$baseName' ($($baseName.Length) chars)"
        Write-Host "  • Suffix: '$Suffix' ($($Suffix.Length) chars)"
        Write-Host "  • Random suffix: $UseRandom"
        Write-Host "  • Backend suffix: '$backendSuffix' ($($backendSuffix.Length) chars)"
        Write-Host "  • Final random: 8 chars"
        Write-Host ""
        Write-Status "Suggestions to fix:"
        Write-Host "  1. Use shorter prefix (current: $($Prefix.Length) chars)"
        Write-Host "  2. Use shorter suffix (current: $($Suffix.Length) chars)"
        Write-Host "  3. Disable random suffix if not needed"
        Write-Host ""
        Write-ErrorMsg "Please reconfigure with shorter names"
        Write-Host "=================================="
        return $false
    }
    
    Write-Success "Bucket naming validation passed ($totalLength/63 characters)"
    return $true
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    }
    
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "AWS CLI is not installed. Please install and configure AWS CLI"
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

# Function to configure deployment region
function Configure-DeploymentRegion {
    Write-Status ""
    Write-Status "=== Deployment Region Selection ==="
    Write-Status "Select the AWS region where infrastructure will be deployed."
    Write-Status "Note: AWS Health API will always use us-east-1 regardless of deployment region."
    Write-Status ""
    
    $deployRegions = @("us-east-1", "ap-southeast-1")
    $deployDescriptions = @(
        "US East (N. Virginia) - Uses us.anthropic.* Bedrock models",
        "Asia Pacific (Singapore) - Uses apac.anthropic.* Bedrock models"
    )
    
    Write-Status "Available deployment regions:"
    for ($i = 0; $i -lt $deployRegions.Count; $i++) {
        Write-Host "  $($i+1)) $($deployRegions[$i]) - $($deployDescriptions[$i])"
    }
    
    Write-Host ""
    do {
        $choice = Read-Host "Select deployment region (1-$($deployRegions.Count))"
        $choiceNum = [int]$choice
    } while ($choiceNum -lt 1 -or $choiceNum -gt $deployRegions.Count)
    
    $script:DeploymentRegion = $deployRegions[$choiceNum - 1]
    Write-Success "Selected deployment region: $script:DeploymentRegion"
    
    if ($script:DeploymentRegion -eq "us-east-1") {
        $script:BedrockRegionPrefix = "us"
        Write-Status "Bedrock models will use '$script:BedrockRegionPrefix.anthropic.*' prefix"
    } elseif ($script:DeploymentRegion -eq "ap-southeast-1") {
        $script:BedrockRegionPrefix = "apac"
        Write-Status "Bedrock models will use '$script:BedrockRegionPrefix.anthropic.*' prefix (except Claude 3.5 Sonnet)"
    }
}

# Function to configure health monitoring regions
function Configure-HealthMonitoringRegions {
    Write-Status ""
    Write-Status "=== AWS Health Event Monitoring Configuration ==="
    Write-Status "Select regions to monitor for AWS Health events."
    Write-Status "Note: us-east-1 is always included as the processing region."
    Write-Status ""
    
    $regions = @(
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1",
        "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3", "ap-south-1",
        "ca-central-1", "sa-east-1"
    )
    
    $descriptions = @(
        "US East (N. Virginia)", "US East (Ohio)", "US West (N. California)", "US West (Oregon)",
        "Europe (Ireland)", "Europe (London)", "Europe (Paris)", "Europe (Frankfurt)", "Europe (Stockholm)",
        "Asia Pacific (Singapore)", "Asia Pacific (Sydney)", "Asia Pacific (Tokyo)", "Asia Pacific (Seoul)", 
        "Asia Pacific (Osaka)", "Asia Pacific (Mumbai)",
        "Canada (Central)", "South America (São Paulo)"
    )
    
    Write-Status "Available regions:"
    for ($i = 0; $i -lt $regions.Count; $i++) {
        $num = "{0,2}" -f ($i+1)
        $region = "{0,-20}" -f $regions[$i]
        $desc = $descriptions[$i]
        if ($regions[$i] -eq "us-east-1") {
            Write-Host "  $num) $region $desc (always included)"
        } else {
            Write-Host "  $num) $region $desc"
        }
    }
    
    Write-Host ""
    $num1 = "{0,2}" -f ($regions.Count+1)
    $num2 = "{0,2}" -f ($regions.Count+2)
    $num3 = "{0,2}" -f ($regions.Count+3)
    $num4 = "{0,2}" -f ($regions.Count+4)
    $num5 = "{0,2}" -f ($regions.Count+5)
    $num6 = "{0,2}" -f ($regions.Count+6)
    Write-Host "  $num1) All regions"
    Write-Host "  $num2) Common regions     (us-east-1, us-west-2, eu-west-1)"
    Write-Host "  $num3) US regions only"
    Write-Host "  $num4) EU regions only"
    Write-Host "  $num5) Custom selection"
    Write-Host "  $num6) Skip               (us-east-1 only)"
    
    Write-Status ""
    $choice = Read-Host "Select option (1-$($regions.Count+6))"
    $choiceNum = [int]$choice
    
    $selectedRegions = @("us-east-1")
    
    switch ($choiceNum) {
        ($regions.Count+1) {
            $selectedRegions = $regions
            Write-Status "Selected: All regions"
        }
        ($regions.Count+2) {
            $selectedRegions = @("us-east-1", "us-west-2", "eu-west-1")
            Write-Status "Selected: Common regions"
        }
        ($regions.Count+3) {
            $selectedRegions = @("us-east-1", "us-east-2", "us-west-1", "us-west-2")
            Write-Status "Selected: US regions only"
        }
        ($regions.Count+4) {
            $selectedRegions = @("us-east-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1")
            Write-Status "Selected: EU regions"
        }
        ($regions.Count+5) {
            Write-Status "Custom selection mode:"
            Write-Status "Enter region numbers separated by spaces (e.g., 1 4 5):"
            Write-Status "us-east-1 is automatically included."
            $customChoices = Read-Host
            
            $selectedRegions = @("us-east-1")
            foreach ($num in $customChoices -split '\s+') {
                $numInt = [int]$num
                if ($numInt -ge 1 -and $numInt -le $regions.Count) {
                    $region = $regions[$numInt - 1]
                    if ($region -ne "us-east-1" -and $selectedRegions -notcontains $region) {
                        $selectedRegions += $region
                    }
                }
            }
            Write-Status "Selected regions: $($selectedRegions -join ', ')"
        }
        ($regions.Count+6) {
            $selectedRegions = @("us-east-1")
            Write-Status "Selected: us-east-1 only"
        }
        default {
            if ($choiceNum -ge 1 -and $choiceNum -le $regions.Count) {
                $selectedRegion = $regions[$choiceNum - 1]
                if ($selectedRegion -ne "us-east-1") {
                    $selectedRegions += $selectedRegion
                }
                Write-Status "Selected: $($selectedRegions -join ', ')"
            } else {
                Write-Warning "Invalid choice. Using us-east-1 only."
                $selectedRegions = @("us-east-1")
            }
        }
    }
    
    # Validate AWS Health API access
    Write-Status "Validating AWS Health API access..."
    try {
        aws health describe-events --region us-east-1 --max-items 1 2>$null | Out-Null
        Write-Status "AWS Health API access confirmed"
        Write-Status "All selected regions will be configured for EventBridge health event monitoring"
    } catch {
        Write-Warning "AWS Health API access test failed. This might be due to:"
        Write-Warning "1. Organization Health Dashboard not enabled"
        Write-Warning "2. Insufficient permissions"
        Write-Warning "3. No AWS Business/Enterprise support plan"
        Write-Status "Proceeding with selected regions - EventBridge rules will still be created"
    }
    
    Write-Success "Validated regions: $($selectedRegions -join ', ')"
    
    # Convert to Terraform list format
    $terraformRegions = "[`"$($selectedRegions -join '", "')`"]"
    
    # Append to terraform.tfvars
    Add-Content -Path $script:TfvarsFile -Value "`n# Health Event Monitoring Regions`nhealth_monitoring_regions = $terraformRegions"
    
    Write-Success "Health monitoring regions configured: $($selectedRegions -join ', ')"
}

# Function to configure frontend build and upload
function Configure-FrontendBuildUpload {
    Write-Status ""
    Write-Status "=== Frontend Build and Upload Configuration ==="
    Write-Status "Configure whether to automatically build and deploy the React frontend to S3."
    Write-Status ""
    
    Write-Status "Options:"
    Write-Host "  1) Yes - Build and upload frontend automatically during deployment"
    Write-Host "  2) No  - Skip frontend build/upload (manual deployment required)"
    Write-Host ""
    
    do {
        $choice = Read-Host "Build and upload frontend automatically? (Y/n)"
        if ($choice -match '^[Yy]' -or $choice -eq "") {
            $buildAndUpload = "true"
            Write-Success "Frontend will be built and uploaded automatically"
            break
        } elseif ($choice -match '^[Nn]') {
            $buildAndUpload = "false"
            Write-Status "Frontend build/upload will be skipped"
            break
        } else {
            Write-Warning "Please answer yes (y) or no (n)"
        }
    } while ($true)
    
    Add-Content -Path $script:TfvarsFile -Value "`n# Frontend Build and Upload Configuration`nbuild_and_upload = $buildAndUpload"
    
    Write-Success "Frontend configuration saved"
}

# Function to list available Bedrock models (for troubleshooting)
function Get-AvailableBedrockModels {
    param(
        [string]$DeploymentRegion
    )
    
    Write-Status "Checking available Bedrock models in region: $DeploymentRegion"
    
    try {
        aws bedrock list-foundation-models `
            --region $DeploymentRegion `
            --output table `
            --query 'modelSummaries[?contains(modelId, `anthropic`)].{ModelId:modelId,ModelName:modelName,Status:modelLifecycle.status}' 2>$null
        
        Write-Host ""
        Write-Status "To enable model access, visit: https://console.aws.amazon.com/bedrock/home?region=$DeploymentRegion#/modelaccess"
    } catch {
        Write-Warning "Could not list Bedrock models. This might be due to insufficient permissions."
    }
}

# Function to validate Bedrock model access
function Test-BedrockAccess {
    param(
        [string]$DeploymentRegion,
        [string]$BedrockModelId
    )
    
    Write-Status "Validating Bedrock model access..."
    Write-Status "Checking access to model: $BedrockModelId in region: $DeploymentRegion"
    
    $testPayload = '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}'
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        aws bedrock-runtime invoke-model `
            --region $DeploymentRegion `
            --model-id $BedrockModelId `
            --body $testPayload `
            --cli-binary-format raw-in-base64-out `
            $tempFile 2>$null | Out-Null
        
        Write-Success "Bedrock model access validated: $BedrockModelId"
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        return $true
    } catch {
        Write-ErrorMsg "❌ Bedrock model access validation failed!"
        Write-ErrorMsg "Model: $BedrockModelId"
        Write-ErrorMsg "Region: $DeploymentRegion"
        Write-Host ""
        
        # Show available models for troubleshooting
        Get-AvailableBedrockModels -DeploymentRegion $DeploymentRegion
        Write-Host ""
        
        Write-Status "🔧 To fix this issue:"
        Write-Host "1. Go to AWS Console → Amazon Bedrock → Model access"
        Write-Host "2. Navigate to the '$DeploymentRegion' region"
        Write-Host "3. Request access to the following models:"
        
        if ($DeploymentRegion -eq "us-east-1") {
            Write-Host "   • Claude Sonnet 4 (us.anthropic.claude-sonnet-4-20250514-v1:0)"
            Write-Host "   • Claude 3.7 Sonnet (us.anthropic.claude-3-7-sonnet-20250219-v1:0)"
        } elseif ($DeploymentRegion -eq "ap-southeast-1") {
            Write-Host "   • Claude Sonnet 4 (apac.anthropic.claude-sonnet-4-20250514-v1:0)"
            Write-Host "   • Claude 3.7 Sonnet (apac.anthropic.claude-3-7-sonnet-20250219-v1:0)"
            Write-Host "   • Claude 3.5 Sonnet (anthropic.claude-3-5-sonnet-20240620-v1:0)"
        }
        
        Write-Host "4. Wait for approval (usually instant for Claude models)"
        Write-Host "5. Re-run this deployment script"
        Write-Host ""
        Write-Status "📖 More info: https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html"
        
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        return $false
    }
}

# Function to check Bedrock access for existing configuration
function Test-ExistingBedrockAccess {
    $tfvarsFile = "environment\terraform.tfvars"
    
    if (Test-Path $tfvarsFile) {
        $content = Get-Content $tfvarsFile -Raw
        
        # Extract deployment region and bedrock model from existing config
        $existingRegion = ""
        $existingModel = ""
        
        if ($content -match 'aws_region\s*=\s*"([^"]+)"') {
            $existingRegion = $matches[1]
        }
        if ($content -match 'bedrock_model_id\s*=\s*"([^"]+)"') {
            $existingModel = $matches[1]
        }
        
        if ($existingRegion -and $existingModel) {
            Write-Status "Found existing Bedrock configuration:"
            Write-Status "  Region: $existingRegion"
            Write-Status "  Model: $existingModel"
            
            if (-not (Test-BedrockAccess -DeploymentRegion $existingRegion -BedrockModelId $existingModel)) {
                Write-ErrorMsg "Existing Bedrock model configuration is not accessible"
                Write-Status "Please enable model access or reconfigure with a different model"
                exit 1
            }
        }
    }
}

# Function to configure Bedrock model
function Configure-BedrockModel {
    Write-Status ""
    Write-Status "=== Bedrock Model Selection ==="
    Write-Status "Select the Claude model to use for AWS Health event analysis."
    Write-Status "Models are automatically configured for deployment region: $script:DeploymentRegion"
    Write-Status ""
    
    if ($script:DeploymentRegion -eq "us-east-1") {
        $models = @(
            "us.anthropic.claude-sonnet-4-20250514-v1:0",
            "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
        )
        $modelNames = @("Claude Sonnet 4 (Latest)", "Claude 3.7 Sonnet")
        $modelDescriptions = @(
            "Most advanced model with best analysis quality",
            "Balanced performance and cost"
        )
        $script:BedrockRegionPrefix = "us"
    } elseif ($script:DeploymentRegion -eq "ap-southeast-1") {
        $models = @(
            "apac.anthropic.claude-sonnet-4-20250514-v1:0",
            "apac.anthropic.claude-3-7-sonnet-20250219-v1:0",
            "anthropic.claude-3-5-sonnet-20240620-v1:0"
        )
        $modelNames = @("Claude Sonnet 4 (Latest)", "Claude 3.7 Sonnet", "Claude 3.5 Sonnet")
        $modelDescriptions = @(
            "Most advanced model with best analysis quality",
            "Balanced performance and cost",
            "Proven model with good performance"
        )
        $script:BedrockRegionPrefix = "apac"
    } else {
        $models = @(
            "us.anthropic.claude-sonnet-4-20250514-v1:0",
            "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
        )
        $modelNames = @("Claude Sonnet 4 (Latest)", "Claude 3.7 Sonnet")
        $modelDescriptions = @(
            "Most advanced model with best analysis quality",
            "Balanced performance and cost"
        )
        $script:BedrockRegionPrefix = "us"
        Write-Warning "Unknown deployment region, defaulting to US models"
    }
    
    Write-Status "Available models for region $script:DeploymentRegion ($script:BedrockRegionPrefix prefix):"
    for ($i = 0; $i -lt $models.Count; $i++) {
        Write-Host "  $($i+1)) $($modelNames[$i])"
        Write-Host "      Model ID: $($models[$i])"
        Write-Host "      Description: $($modelDescriptions[$i])"
        Write-Host ""
    }
    
    do {
        $choice = Read-Host "Select Bedrock model (1-$($models.Count))"
        $choiceNum = [int]$choice
    } while ($choiceNum -lt 1 -or $choiceNum -gt $models.Count)
    
    $selectedModel = $models[$choiceNum - 1]
    $selectedModelName = $modelNames[$choiceNum - 1]
    Write-Success "Selected: $selectedModelName"
    Write-Status "Model ID: $selectedModel"
    
    if (-not $script:SkipBedrockValidation) {
        if (-not (Test-BedrockAccess -DeploymentRegion $script:DeploymentRegion -BedrockModelId $selectedModel)) {
            Write-ErrorMsg "Cannot proceed with deployment due to Bedrock access issues"
            Write-Status "Please enable model access and try again"
            Write-Status "Or use -SkipBedrockValidation flag to bypass this check"
            exit 1
        }
    } else {
        Write-Warning "Skipping Bedrock model validation (-SkipBedrockValidation flag used)"
    }
    
    Add-Content -Path $script:TfvarsFile -Value "`n# Bedrock Model Configuration`nbedrock_model_id = `"$selectedModel`""
    
    Write-Success "Bedrock model configuration saved"
}

# Function to configure DynamoDB TTL
function Configure-DynamoDbTtl {
    Write-Status ""
    Write-Status "=== DynamoDB Events Table TTL Configuration ==="
    Write-Status "Configure how long AWS Health events are retained in the database."
    Write-Status "After this period, events will be automatically deleted to manage storage costs."
    Write-Status ""
    
    $ttlOptions = @(60, 90, 180)
    $ttlDescriptions = @("60 days (2 months)", "90 days (3 months)", "180 days (6 months)")
    
    Write-Status "Available retention periods:"
    for ($i = 0; $i -lt $ttlOptions.Count; $i++) {
        Write-Host "  $($i+1)) $($ttlDescriptions[$i])"
    }
    
    Write-Host ""
    do {
        $choice = Read-Host "Select TTL retention period (1-$($ttlOptions.Count))"
        $choiceNum = [int]$choice
    } while ($choiceNum -lt 1 -or $choiceNum -gt $ttlOptions.Count)
    
    $selectedTtlDays = $ttlOptions[$choiceNum - 1]
    $selectedTtlDescription = $ttlDescriptions[$choiceNum - 1]
    Write-Success "Selected: $selectedTtlDescription"
    
    Add-Content -Path $script:TfvarsFile -Value "`n# DynamoDB TTL Configuration`nevents_table_ttl_days = $selectedTtlDays"
    
    Write-Success "DynamoDB TTL configuration saved"
}

# Function to configure email notifications
function Configure-EmailNotifications {
    Write-Status ""
    Write-Status "=== Email Notification Configuration ==="
    Write-Status "Configure scheduled email summaries of open AWS Health events."
    Write-Status "Emails will be sent weekly with a summary and Excel attachment."
    Write-Status ""
    
    do {
        $enableChoice = Read-Host "Enable email notifications? (y/N)"
        if ($enableChoice -match '^[Yy]') {
            $enableEmailNotifications = "true"
            Write-Success "Email notifications will be enabled"
            break
        } elseif ($enableChoice -match '^[Nn]' -or $enableChoice -eq "") {
            $enableEmailNotifications = "false"
            Write-Status "Email notifications will be disabled"
            
            $emailConfig = @"

# Email Notification Configuration (optional)
enable_email_notifications = false                # Set to true to enable email notifications
# sender_email = "your-verified-email@example.com"  # Must be verified in SES (required if enabled)
# master_recipient_email = "admin@example.com"      # Receives all health event summaries (required if enabled)
# email_schedule_expression = "cron(0 1 ? * MON *)" # Monday 9 AM UTC+8 = Monday 1 AM UTC
"@
            Add-Content -Path $script:TfvarsFile -Value $emailConfig
            Write-Success "Email notification configuration saved (disabled)"
            return
        } else {
            Write-Warning "Please answer yes (y) or no (n)"
        }
    } while ($true)
    
    Write-Status ""
    Write-Status "Email notifications require:"
    Write-Status "1. A verified sender email address in Amazon SES"
    Write-Status "2. A master recipient email address"
    Write-Status "3. A schedule for sending reports (default: Monday 9 AM UTC+8)"
    Write-Status ""
    
    # Get sender email
    do {
        $senderEmail = Read-Host "Enter sender email address (must be verified in SES)"
        if ($senderEmail -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'$') {
            Write-Success "Sender email: $senderEmail"
            break
        } else {
            Write-Warning "Invalid email format. Please try again."
        }
    } while ($true)
    
    # Get master recipient email
    do {
        $masterRecipientEmail = Read-Host "Enter master recipient email address"
        if ($masterRecipientEmail -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'$') {
            Write-Success "Master recipient email: $masterRecipientEmail"
            break
        } else {
            Write-Warning "Invalid email format. Please try again."
        }
    } while ($true)
    
    # Configure schedule
    Write-Status ""
    Write-Status "Email Schedule Options:"
    Write-Host "  1) Weekly - Monday 9 AM UTC+8 (Monday 1 AM UTC)"
    Write-Host "  2) Weekly - Friday 9 AM UTC+8 (Friday 1 AM UTC)"
    Write-Host "  3) Daily - 9 AM UTC+8 (1 AM UTC)"
    Write-Host "  4) Custom cron expression"
    Write-Host ""
    
    do {
        $scheduleChoice = Read-Host "Select schedule option (1-4)"
        switch ($scheduleChoice) {
            "1" {
                $emailSchedule = "cron(0 1 ? * MON *)"
                Write-Success "Selected: Weekly - Monday 9 AM UTC+8"
                break
            }
            "2" {
                $emailSchedule = "cron(0 1 ? * FRI *)"
                Write-Success "Selected: Weekly - Friday 9 AM UTC+8"
                break
            }
            "3" {
                $emailSchedule = "cron(0 1 * * ? *)"
                Write-Success "Selected: Daily - 9 AM UTC+8"
                break
            }
            "4" {
                $customCron = Read-Host "Enter custom cron expression"
                $emailSchedule = $customCron
                Write-Success "Selected: Custom - $customCron"
                break
            }
            default {
                Write-Warning "Invalid choice. Please enter 1-4."
                continue
            }
        }
        break
    } while ($true)
    
    $emailConfig = @"

# Email Notification Configuration
enable_email_notifications = true
sender_email = "$senderEmail"
master_recipient_email = "$masterRecipientEmail"
email_schedule_expression = "$emailSchedule"
"@
    Add-Content -Path $script:TfvarsFile -Value $emailConfig
    
    Write-Success "Email notification configuration saved"
    Write-Status ""
    Write-Warning "⚠️  IMPORTANT: Email Verification Required"
    Write-Status ""
    Write-Status "Before deployment, you must verify email addresses in Amazon SES:"
    Write-Status "  • Sender email: $senderEmail"
    Write-Status "  • Recipient email: $masterRecipientEmail (required if SES is in sandbox mode)"
    Write-Status ""
    Write-Status "To verify emails, use one of these methods:"
    Write-Status ""
    Write-Status "Option 1 - AWS CLI:"
    Write-Status "  aws ses verify-email-identity --email-address $senderEmail"
    Write-Status "  aws ses verify-email-identity --email-address $masterRecipientEmail"
    Write-Status ""
    Write-Status "Option 2 - AWS Console:"
    Write-Status "  Go to: AWS Console → Amazon SES → Verified identities → Create identity"
    Write-Status ""
}

# Function to configure deployment
function Configure-Deployment {
    if ($script:RedeployMode) {
        Write-Status "Using existing configuration (redeploy mode)"
        return
    }
    
    Write-Status "Configuring deployment settings..."
    
    $script:TfvarsFile = "environment\terraform.tfvars"
    
    if (Test-Path $script:TfvarsFile) {
        Write-Warning "Configuration file already exists: $script:TfvarsFile"
        Write-Status "Current configuration:"
        Write-Host "=================================="
        Get-Content $script:TfvarsFile
        Write-Host "=================================="
        
        # Extract and display health monitoring regions in a user-friendly way
        $content = Get-Content $script:TfvarsFile -Raw
        if ($content -match 'health_monitoring_regions\s*=\s*\[(.*?)\]') {
            $regionsMatch = $matches[1]
            $regions = $regionsMatch -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ }
            if ($regions) {
                Write-Status "Health Monitoring Regions:"
                foreach ($region in $regions) {
                    Write-Host "  • $region"
                }
                Write-Host "=================================="
            }
        }
        
        # Extract and display environment information
        if ($content -match 'environment\s*=\s*"([^"]+)"') {
            $environmentValue = $matches[1]
            $stageValue = ""
            if ($content -match 'stage_name\s*=\s*"([^"]+)"') {
                $stageValue = $matches[1]
            }
            Write-Status "Environment Configuration:"
            Write-Host "  • Environment: $environmentValue"
            Write-Host "  • Stage: $stageValue"
            Write-Host "=================================="
        }
        
        # Extract and display frontend build configuration
        if ($content -match 'build_and_upload\s*=\s*(true|false)') {
            $buildUploadValue = $matches[1]
            Write-Status "Frontend Build & Upload:"
            if ($buildUploadValue -eq "true") {
                Write-Host "  • ✅ Enabled - Frontend will be built and uploaded automatically"
            } else {
                Write-Host "  • ❌ Disabled - Frontend build/upload will be skipped"
            }
            Write-Host "=================================="
        }
        
        # Extract and display email notification configuration
        if ($content -match 'enable_email_notifications\s*=\s*(true|false)') {
            $emailEnabled = $matches[1]
            Write-Status "Email Notifications:"
            if ($emailEnabled -eq "true") {
                $senderEmailValue = ""
                $masterEmailValue = ""
                $scheduleValue = ""
                if ($content -match 'sender_email\s*=\s*"([^"]+)"') {
                    $senderEmailValue = $matches[1]
                }
                if ($content -match 'master_recipient_email\s*=\s*"([^"]+)"') {
                    $masterEmailValue = $matches[1]
                }
                if ($content -match 'email_schedule_expression\s*=\s*"([^"]+)"') {
                    $scheduleValue = $matches[1]
                }
                Write-Host "  • ✅ Enabled - Weekly email summaries will be sent"
                Write-Host "  • Sender: $senderEmailValue"
                Write-Host "  • Recipient: $masterEmailValue"
                Write-Host "  • Schedule: $scheduleValue"
            } else {
                Write-Host "  • ❌ Disabled - No email notifications will be sent"
            }
            Write-Host "=================================="
        }
        
        # Extract and display Bedrock model configuration
        if ($content -match 'bedrock_model_id\s*=\s*"([^"]+)"') {
            $bedrockModelValue = $matches[1]
            $awsRegionValue = ""
            if ($content -match 'aws_region\s*=\s*"([^"]+)"') {
                $awsRegionValue = $matches[1]
            }
            Write-Status "Bedrock Model Configuration:"
            Write-Host "  • Model ID: $bedrockModelValue"
            Write-Host "  • Deployment Region: $awsRegionValue"
            
            # Determine model name based on model ID
            if ($bedrockModelValue -match 'claude-sonnet-4-20250514-v1:0') {
                Write-Host "  • Model Name: Claude Sonnet 4 (Latest)"
            } elseif ($bedrockModelValue -match 'claude-3-7-sonnet-20250219-v1:0') {
                Write-Host "  • Model Name: Claude 3.7 Sonnet"
            } elseif ($bedrockModelValue -match 'claude-3-5-sonnet-20240620-v1:0') {
                Write-Host "  • Model Name: Claude 3.5 Sonnet"
            } else {
                Write-Host "  • Model Name: Custom/Unknown"
            }
            
            # Show region prefix
            if ($bedrockModelValue -match '^us\.anthropic\.') {
                Write-Host "  • Region Prefix: us (US models)"
            } elseif ($bedrockModelValue -match '^apac\.anthropic\.') {
                Write-Host "  • Region Prefix: apac (Asia Pacific models)"
            } elseif ($bedrockModelValue -match '^anthropic\.claude-3-5-sonnet') {
                Write-Host "  • Region Prefix: none (Direct model access, no cross-region inference)"
            } else {
                Write-Host "  • Region Prefix: Unknown"
            }
            Write-Host "=================================="
        }
        
        $response = Read-Host "Do you want to reconfigure? (y/N)"
        if ($response -notmatch '^[yY]') {
            Write-Status "Using existing configuration"
            $script:UsingExistingConfig = $true
            return
        }
    }
    
    if (-not $script:SelectedAwsProfile) {
        Setup-AwsProfile
    }
    
    do {
        $envName = Read-Host "Enter environment name (e.g., 'dev', 'staging', 'prod')"
    } while (-not $envName)
    
    Write-Success "Environment: $envName"
    
    $resourcePrefix = Read-Host "Enter resource prefix (e.g., 'mycompany', 'acme') or press Enter for none"
    if (-not $resourcePrefix) {
        $resourcePrefix = ""
    }
    
    $envSuffix = $envName
    Write-Status "Using '$envName' as resource naming suffix for consistency"
    
    $randomSuffix = Read-Host "Add random suffix for uniqueness? (y/N)"
    if ($randomSuffix -match '^[yY]') {
        $useRandom = "true"
    } else {
        $useRandom = "false"
    }
    
    Configure-DeploymentRegion
    
    if (-not $script:DeploymentRegion) {
        Write-Warning "No deployment region selected, using us-east-1 as default"
        $script:DeploymentRegion = "us-east-1"
    }
    Write-Status "Final deployment region: $script:DeploymentRegion"
    
    if (-not (Test-NamingChanges -TfvarsFile $script:TfvarsFile -NewPrefix $resourcePrefix -NewSuffix $envSuffix -NewRandom $useRandom)) {
        $content = Get-Content $script:TfvarsFile -Raw
        if ($content -match 'naming_convention\s*=\s*\{[^}]*prefix\s*=\s*"([^"]*)"') {
            $resourcePrefix = $matches[1]
        }
        if ($content -match 'naming_convention\s*=\s*\{[^}]*suffix\s*=\s*"([^"]*)"') {
            $envSuffix = $matches[1]
        }
        if ($content -match 'naming_convention\s*=\s*\{[^}]*use_random_suffix\s*=\s*(true|false)') {
            $useRandom = $matches[1]
        }
        Write-Status "Using existing naming configuration"
    }
    
    if (-not (Test-BucketNaming -Prefix $resourcePrefix -Suffix $envSuffix -UseRandom $useRandom)) {
        Write-ErrorMsg "Bucket naming validation failed. Please reconfigure."
        exit 1
    }
    
    Write-Status "Creating configuration file..."
    
    $tfvarsContent = @"
# AWS Health Dashboard Configuration
aws_region    = "$script:DeploymentRegion"
aws_profile   = "$script:SelectedAwsProfile"
stage_name    = "$envName"
environment   = "$envName"
project_name  = "health-dashboard"
react_app_domain = "localhost:3000"

# Resource Naming Convention
naming_convention = {
  prefix    = "$resourcePrefix"
  suffix    = "$envSuffix"
  separator = "-"
  use_random_suffix = $useRandom
}
"@
    
    Set-Content -Path $script:TfvarsFile -Value $tfvarsContent
    Write-Success "Configuration saved to $script:TfvarsFile"
    
    Configure-HealthMonitoringRegions
    Configure-FrontendBuildUpload
    Configure-BedrockModel
    Configure-DynamoDbTtl
    Configure-EmailNotifications
    
    if ($resourcePrefix -or $envSuffix -or $useRandom -eq "true") {
        Write-Status "Resource naming preview:"
        $nameParts = "health-dashboard"
        if ($resourcePrefix) { $nameParts = "$resourcePrefix-$nameParts" }
        if ($envSuffix) { $nameParts = "$nameParts-$envSuffix" }
        if ($useRandom -eq "true") { $nameParts = "$nameParts-[random]" }
        Write-Host "  Example: $nameParts-lambda-function"
    }
}

# Function to setup backend
function Setup-Backend {
    Write-Status "Setting up Terraform backend (S3 + DynamoDB)..."
    
    try {
        aws sts get-caller-identity | Out-Null
    } catch {
        Write-ErrorMsg "AWS credentials failed"
        exit 1
    }
    
    Push-Location backend-setup
    
    try {
        terraform init -upgrade
        
        if (-not (Test-Path "terraform.tfstate")) {
            Write-Status "Initializing backend terraform..."
            terraform init
            
            Write-Status "Creating backend resources..."
            
            if (Test-Path "..\environment\terraform.tfvars") {
                $content = Get-Content "..\environment\terraform.tfvars" -Raw
                
                $awsRegion = if ($content -match 'aws_region\s*=\s*"([^"]+)"') { $matches[1] } else { "us-east-1" }
                $projectName = if ($content -match 'project_name\s*=\s*"([^"]+)"') { $matches[1] } else { "health-dashboard" }
                $prefix = if ($content -match 'naming_convention\s*=\s*\{[^}]*prefix\s*=\s*"([^"]*)"') { $matches[1] } else { "" }
                $suffix = if ($content -match 'naming_convention\s*=\s*\{[^}]*suffix\s*=\s*"([^"]*)"') { $matches[1] } else { "" }
                $useRandomSuffix = if ($content -match 'naming_convention\s*=\s*\{[^}]*use_random_suffix\s*=\s*(true|false)') { $matches[1] } else { "false" }
                
                $backendVarsContent = @"
aws_region = "$awsRegion"
project_name = "$projectName"
naming_convention = {
  prefix    = "$prefix"
  suffix    = "$suffix"
  separator = "-"
  use_random_suffix = $useRandomSuffix
}
"@
                Set-Content -Path "temp_backend_vars.tfvars" -Value $backendVarsContent
                $backendVars = "-var-file=temp_backend_vars.tfvars"
            } else {
                $backendVarsContent = @"
aws_region = "$($script:DeploymentRegion)"
project_name = "health-dashboard"
naming_convention = {
  prefix    = "$resourcePrefix"
  suffix    = "$envSuffix"
  separator = "-"
  use_random_suffix = $useRandom
}
"@
                Set-Content -Path "temp_backend_vars.tfvars" -Value $backendVarsContent
                $backendVars = "-var-file=temp_backend_vars.tfvars"
            }
            
            terraform apply -auto-approve -var="aws_profile=$script:SelectedAwsProfile" $backendVars
            
            if (Test-Path "temp_backend_vars.tfvars") {
                Remove-Item "temp_backend_vars.tfvars"
            }
            
            $s3Bucket = terraform output -raw s3_bucket_name 2>$null
            $dynamoDbTable = terraform output -raw dynamodb_table_name 2>$null
            $backendRandomSuffix = terraform output -raw random_suffix 2>$null
            
            if (-not $s3Bucket -or -not $dynamoDbTable) {
                Write-ErrorMsg "Failed to get backend outputs"
                Pop-Location
                exit 1
            }
            
            Write-Success "Backend setup complete"
            Write-Status "S3 Bucket: $s3Bucket"
            Write-Status "DynamoDB Table: $dynamoDbTable"
            
            $backendConfig = @"
`$env:TF_BACKEND_BUCKET = '$s3Bucket'
`$env:TF_BACKEND_TABLE = '$dynamoDbTable'
`$env:TF_BACKEND_RANDOM_SUFFIX = '$backendRandomSuffix'
"@
            Set-Content -Path "..\backend-config.ps1" -Value $backendConfig
            Write-Success "Backend configuration stored"
        } else {
            Write-Status "Backend already exists, retrieving configuration..."
            terraform init -upgrade
            
            $s3Bucket = terraform output -raw s3_bucket_name 2>$null
            $dynamoDbTable = terraform output -raw dynamodb_table_name 2>$null
            $backendRandomSuffix = terraform output -raw random_suffix 2>$null
            
            if ($s3Bucket -and $dynamoDbTable) {
                $backendConfig = @"
`$env:TF_BACKEND_BUCKET = '$s3Bucket'
`$env:TF_BACKEND_TABLE = '$dynamoDbTable'
`$env:TF_BACKEND_RANDOM_SUFFIX = '$backendRandomSuffix'
"@
                Set-Content -Path "..\backend-config.ps1" -Value $backendConfig
                Write-Success "Using existing backend configuration"
                Write-Status "S3 Bucket: $s3Bucket"
                Write-Status "DynamoDB Table: $dynamoDbTable"
            } else {
                Write-ErrorMsg "Backend exists but configuration not readable. Please run '.\deploy.ps1 cleanup' and try again."
                Pop-Location
                exit 1
            }
        }
    } finally {
        Pop-Location
    }
}

# Function to build and upload frontend
function Build-AndUploadFrontend {
    $tfvarsFile = "terraform.tfvars"
    
    Write-Status "Checking frontend build configuration..."
    
    if (Test-Path $tfvarsFile) {
        $content = Get-Content $tfvarsFile -Raw
        $buildUploadValue = "false"
        
        if ($content -match 'build_and_upload\s*=\s*(true|false)') {
            $buildUploadValue = $matches[1]
        }
        
        Write-Status "Found build_and_upload = $buildUploadValue"
        
        if ($buildUploadValue -eq "true") {
            Write-Status "Building and uploading React frontend..."
            
            # Get frontend bucket name from Terraform output
            try {
                $frontendConfigJson = terraform output -json frontend_config 2>$null | ConvertFrom-Json
                $frontendBucket = $frontendConfigJson.s3_bucket_name
                $cloudfrontId = $frontendConfigJson.cloudfront_distribution_id
            } catch {
                $frontendBucket = ""
                $cloudfrontId = ""
            }
            
            Write-Status "Frontend bucket: $frontendBucket"
            Write-Status "CloudFront ID: $cloudfrontId"
            
            if ($frontendBucket) {
                # Build React app
                Write-Status "Building React application..."
                Push-Location "..\..\frontend\app"
                
                try {
                    if (-not (Test-Path "package.json")) {
                        Write-ErrorMsg "Frontend package.json not found at $(Get-Location)"
                        Pop-Location
                        return $false
                    }
                    
                    Write-Status "Installing npm dependencies..."
                    npm install
                    
                    Write-Status "Building React app..."
                    npm run build
                    
                    # Upload to S3
                    Write-Status "Uploading to S3 bucket: $frontendBucket"
                    aws s3 sync dist/ "s3://$frontendBucket/" --delete
                    
                    # Invalidate CloudFront cache
                    if ($cloudfrontId) {
                        Write-Status "Invalidating CloudFront cache: $cloudfrontId"
                        aws cloudfront create-invalidation --distribution-id $cloudfrontId --paths "/*" | Out-Null
                        Write-Success "CloudFront cache invalidated"
                    }
                    
                    Write-Success "Frontend build and upload completed"
                    return $true
                } finally {
                    Pop-Location
                    Push-Location "..\..\backend\environment"
                }
            } else {
                Write-Warning "Frontend bucket name not found - checking Terraform outputs..."
                terraform output
                return $false
            }
        } else {
            Write-Status "Frontend build disabled (build_and_upload = $buildUploadValue)"
            return $true
        }
    } else {
        Write-Warning "terraform.tfvars file not found at $(Get-Location)\$tfvarsFile"
        return $false
    }
}

# Function to deploy infrastructure
function Deploy-Infrastructure {
    Write-Status "Deploying infrastructure..."
    
    if (-not (Test-Path "backend-config.ps1")) {
        Write-ErrorMsg "Backend configuration not found. Run setup first."
        exit 1
    }
    
    . .\backend-config.ps1
    
    Push-Location environment
    
    try {
        # Get deployment region from tfvars
        $deployRegion = "us-east-1"
        if (Test-Path "terraform.tfvars") {
            $content = Get-Content "terraform.tfvars" -Raw
            if ($content -match 'aws_region\s*=\s*"([^"]+)"') {
                $deployRegion = $matches[1]
            }
        }
        
        Write-Status "Initializing Terraform with backend..."
        terraform init `
            -backend-config="bucket=$env:TF_BACKEND_BUCKET" `
            -backend-config="key=environment/terraform.tfstate" `
            -backend-config="region=$deployRegion" `
            -backend-config="dynamodb_table=$env:TF_BACKEND_TABLE" `
            -migrate-state
        
        Write-Status "Planning deployment..."
        terraform plan `
            -var="s3_backend_bucket=$env:TF_BACKEND_BUCKET" `
            -var="dynamodb_backend_table=$env:TF_BACKEND_TABLE" `
            -var="backend_random_suffix=$env:TF_BACKEND_RANDOM_SUFFIX" `
            -out=tfplan
        
        if ($script:RedeployMode) {
            Write-Status "Auto-applying changes (redeploy mode)..."
            terraform apply -auto-approve tfplan
            Remove-Item tfplan -ErrorAction SilentlyContinue
        } else {
            Write-Status "Review the plan above. Do you want to continue? (y/N)"
            $response = Read-Host
            if ($response -match '^[yY]') {
                terraform apply tfplan
                Remove-Item tfplan -ErrorAction SilentlyContinue
            } else {
                Write-Warning "Deployment cancelled"
                Remove-Item tfplan -ErrorAction SilentlyContinue
                exit 0
            }
        }
        
        Write-Success "Infrastructure deployed successfully!"
        
        # Build and upload frontend after infrastructure deployment
        Build-AndUploadFrontend
        
        # Check if this is an initial deployment or redeployment
        $initialDeployment = $false
        
        if (-not (Test-Path ".deployment_marker")) {
            $initialDeployment = $true
            # Create marker file for future runs
            Set-Content -Path ".deployment_marker" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Write-Status "Initial deployment detected"
        } else {
            Write-Status "Redeployment detected - skipping Lambda invocation"
        }
        
        # Only trigger Lambda function on initial deployment
        if ($initialDeployment) {
            Write-Status "Triggering initial health events collection..."
            
            try {
                $eventProcessorName = terraform output -raw event_processor_function_name 2>$null
                
                if ($eventProcessorName) {
                    Write-Status "Invoking function asynchronously: $eventProcessorName"
                    
                    $tempResponse = [System.IO.Path]::GetTempFileName()
                    
                    try {
                        aws lambda invoke `
                            --region $deployRegion `
                            --function-name $eventProcessorName `
                            --invocation-type Event `
                            --payload '{}' `
                            $tempResponse 2>$null | Out-Null
                        
                        Write-Success "Initial health events collection triggered successfully"
                        Write-Status "Monitoring execution progress..."
                        Write-Status "Waiting for function to complete (checking every 30 seconds)..."
                        
                        # Monitor function completion (max 15 minutes)
                        for ($i = 1; $i -le 30; $i++) {
                            Write-Host "." -NoNewline
                            
                            # Calculate start time (5 minutes ago)
                            $startTime = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds()
                            
                            # Get the latest log stream
                            try {
                                $latestLogStream = aws logs describe-log-streams `
                                    --region $deployRegion `
                                    --log-group-name "/aws/lambda/$eventProcessorName" `
                                    --order-by LastEventTime `
                                    --descending `
                                    --limit 1 `
                                    --query 'logStreams[0].logStreamName' `
                                    --output text 2>$null
                                
                                if ($latestLogStream -and $latestLogStream -ne "None") {
                                    $logFilterResult = aws logs filter-log-events `
                                        --region $deployRegion `
                                        --log-group-name "/aws/lambda/$eventProcessorName" `
                                        --log-stream-names $latestLogStream `
                                        --start-time $startTime `
                                        --filter-pattern "END" `
                                        --query 'events[0].message' `
                                        --output text 2>$null
                                    
                                    if ($logFilterResult -match "END RequestId") {
                                        Write-Host ""
                                        Write-Success "Event processor execution completed"
                                        break
                                    }
                                }
                            } catch {
                                # Continue monitoring
                            }
                            
                            if ($i -eq 30) {
                                Write-Host ""
                                Write-Warning "Function may still be running - continuing with deployment"
                                Write-Status "Check CloudWatch logs: /aws/lambda/$eventProcessorName"
                                break
                            }
                            
                            Start-Sleep -Seconds 30
                        }
                        
                        Write-Status "Lambda monitoring process completed"
                    } finally {
                        Remove-Item $tempResponse -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Warning "Event processor function name not found - skipping initial trigger"
                }
            } catch {
                Write-Warning "Failed to invoke Lambda function - events will be collected on next scheduled run"
            }
            
            Write-Success "Initial data collection process completed"
        }
        
        # Check if frontend is enabled
        $buildAndUpload = "false"
        if (Test-Path "terraform.tfvars") {
            $content = Get-Content "terraform.tfvars" -Raw
            if ($content -match 'build_and_upload\s*=\s*(true|false)') {
                $buildAndUpload = $matches[1]
            }
        }
        
        if ($buildAndUpload -eq "true") {
            Write-Status "Your React app:"
            Write-Host "=================================="
            terraform output frontend_config 2>$null
            Write-Host "=================================="
        } else {
            Write-Status "S3 Bucket (for email attachments):"
            Write-Host "=================================="
            try {
                $frontendConfigJson = terraform output -json frontend_config 2>$null | ConvertFrom-Json
                $bucketName = $frontendConfigJson.s3_bucket_name
                if ($bucketName) {
                    Write-Host "s3_bucket_name = `"$bucketName`""
                    Write-Host ""
                    Write-Host "Note: Frontend (CloudFront/API Gateway) not deployed (build_and_upload = false)"
                    Write-Host "      S3 bucket is used for email attachments only"
                } else {
                    Write-Host "S3 bucket not available"
                }
            } catch {
                Write-Host "S3 bucket not available"
            }
            Write-Host "=================================="
        }
        
    } finally {
        Pop-Location
    }
}

# Function to destroy infrastructure with retry
function Invoke-DestroyWithRetry {
    $maxAttempts = 3
    $attempt = 1
    $destroySuccess = $false
    
    # Check if we have a valid terraform configuration
    if (-not (Test-Path "terraform.tfvars") -and -not (Test-Path "main.tf")) {
        Write-ErrorMsg "No terraform configuration found in current directory"
        return $false
    }
    
    while ($attempt -le $maxAttempts -and -not $destroySuccess) {
        Write-Status "Destroy attempt $attempt of $maxAttempts..."
        
        # Refresh state before destroy attempt
        Write-Status "Refreshing Terraform state..."
        try {
            terraform refresh -auto-approve 2>$null | Out-Null
        } catch {
            Write-Warning "State refresh failed, attempting to continue..."
        }
        
        # Attempt destroy
        $destroyCmd = "terraform destroy -auto-approve"
        if (Test-Path "terraform.tfvars") {
            $destroyCmd += " -var-file=terraform.tfvars"
        }
        
        $tempLog = [System.IO.Path]::GetTempFileName()
        
        try {
            $destroyOutput = Invoke-Expression "$destroyCmd 2>&1" | Tee-Object -FilePath $tempLog
            
            # Check if Terraform actually destroyed anything
            if ($destroyOutput -match "Resources: 0 destroyed") {
                Write-Warning "Terraform reports 0 resources destroyed - state may be out of sync"
                Write-Status "Checking if resources actually exist in AWS..."
                
                # Force a state refresh and try again
                terraform refresh -auto-approve 2>$null | Out-Null
                
                # Try destroy again after refresh
                $retryOutput = Invoke-Expression "$destroyCmd 2>&1"
                if ($retryOutput -match "Resources: 0 destroyed") {
                    Write-Warning "Still 0 resources destroyed after refresh - state may be completely out of sync"
                    $destroySuccess = $false
                } else {
                    $destroySuccess = $true
                    Write-Success "Infrastructure destroyed successfully after state refresh"
                }
            } else {
                $destroySuccess = $true
                Write-Success "Infrastructure destroyed successfully"
            }
        } catch {
            Write-Warning "Destroy attempt $attempt failed"
            Write-Status "Last few lines of destroy output:"
            if (Test-Path $tempLog) {
                Get-Content $tempLog -Tail 10
            }
            
            if ($attempt -lt $maxAttempts) {
                Write-Status "Trying targeted destroy for common problematic resources..."
                
                # Try to destroy resources that commonly cause issues
                $problematicResources = @(
                    "aws_lambda_event_source_mapping.event_processing_trigger",
                    "module.lambda.aws_lambda_event_source_mapping.events_stream",
                    "module.api_gateway.aws_lambda_permission.dashboard_api_gateway",
                    "module.api_gateway.aws_lambda_permission.events_api_gateway",
                    "module.api_gateway.aws_lambda_permission.filters_api_gateway",
                    "aws_lambda_permission.eventbridge_cross_region",
                    "module.frontend.null_resource.build_and_upload",
                    "module.frontend.aws_cloudfront_distribution.frontend",
                    "module.api_gateway",
                    "module.lambda",
                    "module.eventbridge_us_east_1_deployment",
                    "module.eventbridge_us_east_1_monitoring",
                    "module.eventbridge_us_east_2",
                    "module.eventbridge_us_west_1",
                    "module.eventbridge_us_west_2",
                    "module.eventbridge_eu_west_1",
                    "module.sqs",
                    "module.dynamodb",
                    "module.frontend",
                    "module.cognito",
                    "module.cloudwatch",
                    "module.iam"
                )
                
                foreach ($resource in $problematicResources) {
                    Write-Status "Attempting to destroy: $resource"
                    try {
                        $targetOutput = terraform destroy -target="$resource" -auto-approve 2>&1
                        if ($targetOutput -match "No instances found") {
                            Write-Status "Resource $resource not found (already destroyed)"
                        } else {
                            Write-Status "Successfully destroyed: $resource"
                        }
                    } catch {
                        Write-Warning "Failed to destroy: $resource"
                    }
                    Start-Sleep -Seconds 2
                }
                
                # Try a state refresh after targeted destroys
                Write-Status "Refreshing state after targeted destroys..."
                terraform refresh -auto-approve 2>$null | Out-Null
                
                Write-Status "Waiting 15 seconds before retry..."
                Start-Sleep -Seconds 15
            }
        } finally {
            Remove-Item $tempLog -ErrorAction SilentlyContinue
        }
        
        $attempt++
    }
    
    if (-not $destroySuccess) {
        Write-ErrorMsg "All destroy attempts failed. Manual cleanup may be required."
        
        # Show what resources are still in state
        Write-Status "Remaining resources in Terraform state:"
        try {
            $stateResources = terraform state list 2>$null
            if ($stateResources) {
                $stateResources | ForEach-Object { Write-Host $_ }
                Write-Host ""
                Write-Status "Detailed troubleshooting steps:"
                Write-Status "1. Check AWS Console for remaining resources"
                Write-Status "2. Try destroying specific resources: terraform destroy -target=<resource_name>"
                Write-Status "3. Check for resources in multiple regions (EventBridge rules)"
                Write-Status "4. Look for dependency issues in the destroy log above"
                Write-Status "5. Use AWS CLI to delete stubborn resources manually"
            } else {
                Write-Warning "Terraform state is empty but AWS resources may still exist!"
                Write-Status "This suggests state corruption or resources created outside Terraform."
                Write-Status "Offering manual cleanup options..."
                
                # Offer manual cleanup
                $manualCleanup = Read-Host "Would you like to attempt manual cleanup of detected resources? (y/N)"
                if ($manualCleanup -match '^[yY]') {
                    Invoke-ManualResourceCleanup
                }
            }
        } catch {
            Write-Warning "Could not check Terraform state"
        }
        
        # Still mark as partially successful to continue with cleanup
        Write-Warning "Continuing with local cleanup despite destroy failures"
    }
    
    return $destroySuccess
}

# Function to check if resources are destroyed
function Test-ResourcesDestroyed {
    Write-Status "Verifying main infrastructure resource destruction..."
    Write-Status "(Note: Backend storage resources are checked separately)"
    
    $resourcesExist = $false
    
    # Try to determine the naming pattern from terraform.tfvars
    $namePattern = "health-dashboard"
    $tfvarsFile = "terraform.tfvars"
    
    if (Test-Path $tfvarsFile) {
        $content = Get-Content $tfvarsFile -Raw
        
        # Extract project name
        $projectName = "health-dashboard"
        if ($content -match 'project_name\s*=\s*"([^"]+)"') {
            $projectName = $matches[1]
        }
        
        # Extract naming convention components
        $prefix = ""
        $suffix = ""
        if ($content -match 'naming_convention\s*=\s*\{[^}]*prefix\s*=\s*"([^"]*)"') {
            $prefix = $matches[1]
        }
        if ($content -match 'naming_convention\s*=\s*\{[^}]*suffix\s*=\s*"([^"]*)"') {
            $suffix = $matches[1]
        }
        
        # Build the expected name pattern
        $namePattern = $projectName
        if ($prefix) { $namePattern = "$prefix-$namePattern" }
        if ($suffix) { $namePattern = "$namePattern-$suffix" }
        
        Write-Status "Looking for resources with pattern: $namePattern"
    } else {
        Write-Warning "terraform.tfvars not found, using default pattern: $namePattern"
    }
    
    # Check Lambda functions (excluding backend-related functions)
    try {
        $lambdaFunctions = aws lambda list-functions `
            --query "Functions[?contains(FunctionName, '$namePattern')].[FunctionName]" `
            --output text 2>$null | Where-Object { $_ -notmatch "backend|terraform" }
        
        if ($lambdaFunctions) {
            Write-Warning "Main infrastructure Lambda functions still exist: $lambdaFunctions"
            $resourcesExist = $true
        }
    } catch {
        # Continue checking
    }
    
    # Check DynamoDB tables (only main infrastructure tables)
    try {
        $allTables = aws dynamodb list-tables --query "TableNames" --output text 2>$null
        $mainInfraTables = @()
        
        foreach ($table in $allTables -split '\s+') {
            if ($table -match "$namePattern.*(events|filters|counts)$" -and $table -notmatch "backend") {
                $mainInfraTables += $table
            }
        }
        
        if ($mainInfraTables.Count -gt 0) {
            Write-Warning "Main infrastructure DynamoDB tables still exist: $($mainInfraTables -join ', ')"
            $resourcesExist = $true
        }
    } catch {
        # Continue checking
    }
    
    # Check API Gateway
    try {
        $apiGateways = aws apigateway get-rest-apis `
            --query "items[?contains(name, '$namePattern')]" `
            --output text 2>$null
        
        if ($apiGateways) {
            Write-Warning "API Gateway still exists"
            $resourcesExist = $true
        }
    } catch {
        # Continue checking
    }
    
    # Check S3 buckets (frontend bucket, excluding backend buckets)
    try {
        $s3Buckets = aws s3 ls 2>$null | 
            Select-String $namePattern | 
            Where-Object { $_ -notmatch "backend|terraform" } |
            ForEach-Object { ($_ -split '\s+')[2] }
        
        if ($s3Buckets) {
            Write-Warning "Main infrastructure S3 buckets still exist: $($s3Buckets -join ', ')"
            $resourcesExist = $true
        }
    } catch {
        # Continue checking
    }
    
    if ($resourcesExist) {
        return $false
    } else {
        Write-Success "Main infrastructure destruction verified (backend storage preserved)"
        return $true
    }
}

# Function to empty S3 buckets before destroy
function Clear-S3BucketsBeforeDestroy {
    param(
        [string]$BackendBucket
    )
    
    Write-Status "Emptying S3 buckets before destroy..."
    
    # Empty backend bucket if provided
    if ($BackendBucket) {
        Write-Status "Emptying backend S3 bucket: $BackendBucket"
        try {
            aws s3 rm "s3://$BackendBucket" --recursive 2>$null | Out-Null
        } catch {
            Write-Warning "Could not empty backend bucket: $BackendBucket"
        }
    }
    
    # Find and empty frontend bucket
    try {
        $frontendBucket = aws s3 ls 2>$null | 
            Select-String "health-dashboard.*frontend" | 
            Select-Object -First 1 |
            ForEach-Object { ($_ -split '\s+')[2] }
        
        if ($frontendBucket) {
            Write-Status "Emptying frontend S3 bucket: $frontendBucket"
            aws s3 rm "s3://$frontendBucket" --recursive 2>$null | Out-Null
        }
    } catch {
        # Continue
    }
    
    Write-Success "S3 buckets emptied"
}

# Function to manually clean up resources when Terraform state is out of sync
function Invoke-ManualResourceCleanup {
    Write-Status "Attempting manual cleanup of detected resources..."
    
    # Try to determine the naming pattern from terraform.tfvars
    $namePattern = "health-dashboard"
    $tfvarsFile = "terraform.tfvars"
    
    if (Test-Path $tfvarsFile) {
        $content = Get-Content $tfvarsFile -Raw
        
        $projectName = "health-dashboard"
        if ($content -match 'project_name\s*=\s*"([^"]+)"') {
            $projectName = $matches[1]
        }
        
        $prefix = ""
        $suffix = ""
        if ($content -match 'naming_convention\s*=\s*\{[^}]*prefix\s*=\s*"([^"]*)"') {
            $prefix = $matches[1]
        }
        if ($content -match 'naming_convention\s*=\s*\{[^}]*suffix\s*=\s*"([^"]*)"') {
            $suffix = $matches[1]
        }
        
        $namePattern = $projectName
        if ($prefix) { $namePattern = "$prefix-$namePattern" }
        if ($suffix) { $namePattern = "$namePattern-$suffix" }
    }
    
    Write-Status "Using pattern: $namePattern"
    
    # Clean up Lambda functions
    Write-Status "Cleaning up Lambda functions..."
    try {
        $lambdaFunctions = aws lambda list-functions `
            --query "Functions[?contains(FunctionName, '$namePattern')].[FunctionName]" `
            --output text 2>$null | Where-Object { $_ -notmatch "backend|terraform" }
        
        foreach ($func in $lambdaFunctions) {
            if ($func) {
                Write-Status "Deleting Lambda function: $func"
                aws lambda delete-function --function-name $func 2>$null
            }
        }
    } catch {
        Write-Warning "Failed to clean up Lambda functions"
    }
    
    # Clean up DynamoDB tables
    Write-Status "Cleaning up DynamoDB tables..."
    try {
        $allTables = aws dynamodb list-tables --query "TableNames" --output text 2>$null
        foreach ($table in $allTables -split '\s+') {
            if ($table -match "$namePattern.*(events|filters|counts)$" -and $table -notmatch "backend") {
                Write-Status "Deleting DynamoDB table: $table"
                aws dynamodb delete-table --table-name $table 2>$null
            }
        }
    } catch {
        Write-Warning "Failed to clean up DynamoDB tables"
    }
    
    # Clean up S3 buckets (frontend)
    Write-Status "Cleaning up S3 buckets..."
    try {
        $s3Buckets = aws s3 ls 2>$null | 
            Select-String $namePattern | 
            Where-Object { $_ -notmatch "backend|terraform" } |
            ForEach-Object { ($_ -split '\s+')[2] }
        
        foreach ($bucket in $s3Buckets) {
            if ($bucket) {
                Write-Status "Emptying and deleting S3 bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive 2>$null
                aws s3 rb "s3://$bucket" 2>$null
            }
        }
    } catch {
        Write-Warning "Failed to clean up S3 buckets"
    }
    
    # Clean up API Gateway
    Write-Status "Cleaning up API Gateway..."
    try {
        $apiIds = aws apigateway get-rest-apis `
            --query "items[?contains(name, '$namePattern')].id" `
            --output text 2>$null
        
        foreach ($apiId in $apiIds -split '\s+') {
            if ($apiId) {
                Write-Status "Deleting API Gateway: $apiId"
                aws apigateway delete-rest-api --rest-api-id $apiId 2>$null
            }
        }
    } catch {
        Write-Warning "Failed to clean up API Gateway"
    }
    
    Write-Status "Manual cleanup completed. Some resources may take time to fully delete."
}

# Function to empty S3 buckets before destroy
function Clear-S3Buckets {
    param(
        [string]$BackendBucket
    )
    
    Write-Status "Emptying S3 buckets before destroy..."
    
    # Empty backend bucket if provided
    if ($BackendBucket) {
        Write-Status "Emptying backend S3 bucket: $BackendBucket"
        aws s3 rm "s3://$BackendBucket" --recursive 2>$null | Out-Null
    }
    
    # Find and empty frontend bucket
    try {
        $frontendBucket = aws s3 ls 2>$null | 
            Select-String "health-dashboard.*frontend" | 
            Select-Object -First 1 |
            ForEach-Object { ($_ -split '\s+')[2] }
        
        if ($frontendBucket) {
            Write-Status "Emptying frontend S3 bucket: $frontendBucket"
            aws s3 rm "s3://$frontendBucket" --recursive 2>$null | Out-Null
        }
    } catch {
        # Continue
    }
    
    Write-Success "S3 buckets emptied"
}

# Function to destroy infrastructure
function Remove-Infrastructure {
    Write-Warning "This will destroy ALL infrastructure. Are you sure? (y/N)"
    $response = Read-Host
    
    if ($response -match '^[yY]') {
        $deployRegion = "us-east-1"
        $envName = "unknown"
        
        if (Test-Path "environment\terraform.tfvars") {
            $content = Get-Content "environment\terraform.tfvars" -Raw
            if ($content -match 'aws_region\s*=\s*"([^"]+)"') {
                $deployRegion = $matches[1]
            }
            if ($content -match 'environment\s*=\s*"([^"]+)"') {
                $envName = $matches[1]
            }
            Write-Status "Detected deployment region: $deployRegion for environment: $envName"
        }
        
        $backendBucket = ""
        $backendTable = ""
        
        if (Test-Path "backend-config.ps1") {
            . .\backend-config.ps1
            $backendBucket = $env:TF_BACKEND_BUCKET
            $backendTable = $env:TF_BACKEND_TABLE
            Write-Status "Found backend config: bucket=$backendBucket, table=$backendTable"
        } else {
            Write-Status "Backend config not found, attempting auto-detection..."
            
            try {
                $s3Buckets = aws s3 ls 2>$null | Select-String "health-dashboard.*terraform-state"
                if ($s3Buckets) {
                    $backendBucket = ($s3Buckets[0] -split '\s+')[2]
                }
                
                $tables = aws dynamodb list-tables --query "TableNames[?contains(@, 'health-dashboard') && contains(@, 'terraform-locks')]" --output text 2>$null
                if ($tables) {
                    $backendTable = ($tables -split '\s+')[0]
                }
                
                if ($backendBucket -and $backendTable) {
                    Write-Status "Auto-detected backend: bucket=$backendBucket, table=$backendTable"
                    
                    $backendConfig = @"
`$env:TF_BACKEND_BUCKET = '$backendBucket'
`$env:TF_BACKEND_TABLE = '$backendTable'
"@
                    Set-Content -Path "backend-config.ps1" -Value $backendConfig
                }
            } catch {
                Write-Warning "Could not auto-detect backend resources"
            }
        }
        
        Write-Status "Destroying main infrastructure..."
        
        if ($backendBucket -and $backendTable) {
            Push-Location environment
            
            try {
                Write-Status "Initializing terraform with backend configuration..."
                
                try {
                    terraform init `
                        -backend-config="bucket=$backendBucket" `
                        -backend-config="key=environment/terraform.tfstate" `
                        -backend-config="region=$deployRegion" 2>$null | Out-Null
                } catch {
                    Write-ErrorMsg "Failed to initialize terraform with backend. Trying local state..."
                    terraform init -migrate-state 2>$null | Out-Null
                }
                
                # Robust destroy with multiple attempts
                $destroyResult = Invoke-DestroyWithRetry
                
                # Check if destroy was actually successful before removing marker
                if (Test-ResourcesDestroyed) {
                    if (Test-Path ".deployment_marker") {
                        Remove-Item ".deployment_marker"
                        Write-Status "Removed deployment marker file"
                    }
                } else {
                    Write-Warning "Some resources may still exist - keeping deployment marker"
                }
            } finally {
                Pop-Location
            }
        } else {
            Write-Warning "Backend not found. Attempting local state destroy..."
            
            Push-Location environment
            
            try {
                if ((Test-Path "terraform.tfstate") -or (Test-Path ".terraform\terraform.tfstate")) {
                    Write-Status "Found local state, attempting destroy..."
                    terraform init 2>$null | Out-Null
                    Invoke-DestroyWithRetry
                    
                    # Clean up deployment marker after local state destroy
                    if (Test-Path ".deployment_marker") {
                        Remove-Item ".deployment_marker"
                        Write-Status "Removed deployment marker file"
                    }
                } else {
                    Write-Warning "No terraform state found. Infrastructure may already be destroyed."
                    
                    # Clean up deployment marker even if no state found
                    if (Test-Path ".deployment_marker") {
                        Remove-Item ".deployment_marker"
                        Write-Status "Removed deployment marker file (no state found)"
                    }
                }
            } finally {
                Pop-Location
            }
        }
        
        $backendResponse = Read-Host "Do you also want to destroy the backend storage (S3 + DynamoDB)? (y/N)"
        
        if ($backendResponse -match '^[yY]') {
            Remove-BackendInfrastructure -BackendBucket $backendBucket -BackendTable $backendTable -DeployRegion $deployRegion
        } else {
            Write-Success "Main infrastructure destroyed (backend preserved)"
        }
        
        # Final cleanup - ensure deployment marker is removed after successful destroy
        if (Test-Path "environment\.deployment_marker") {
            Remove-Item "environment\.deployment_marker"
            Write-Status "Final cleanup: Removed deployment marker file"
        }
    } else {
        Write-Warning "Destruction cancelled"
    }
}

# Function to destroy backend infrastructure
function Remove-BackendInfrastructure {
    param(
        [string]$BackendBucket,
        [string]$BackendTable,
        [string]$DeployRegion
    )
    
    Write-Status "Destroying backend infrastructure..."
    
    if ($BackendBucket -and $BackendTable) {
        # Empty S3 buckets first
        Clear-S3BucketsBeforeDestroy -BackendBucket $BackendBucket
        
        $backendSetupPaths = @(
            "..\backend-setup",
            "backend-setup",
            "..\..\backend-setup"
        )
        
        $backendSetupDir = $null
        foreach ($path in $backendSetupPaths) {
            if (Test-Path $path) {
                $backendSetupDir = $path
                break
            }
        }
        
        if (-not $backendSetupDir) {
            Write-ErrorMsg "Cannot find backend-setup directory"
            exit 1
        }
        
        Push-Location $backendSetupDir
        
        try {
            Write-Status "Changed to backend-setup directory: $(Get-Location)"
            
            if (-not (Test-Path "terraform.tfstate")) {
                Write-Status "Recreating backend state for safe destruction..."
                terraform init 2>$null | Out-Null
                
                # Import existing resources into terraform state
                terraform import -var="aws_profile=$script:SelectedAwsProfile" -var="aws_region=$DeployRegion" aws_s3_bucket.terraform_state $BackendBucket 2>$null | Out-Null
                terraform import -var="aws_profile=$script:SelectedAwsProfile" -var="aws_region=$DeployRegion" aws_dynamodb_table.terraform_locks $BackendTable 2>$null | Out-Null
                
                # Try to extract and import random suffix
                if ($BackendBucket -match '([a-f0-9]{8})$') {
                    $randomSuffix = $matches[1]
                    terraform import -var="aws_profile=$script:SelectedAwsProfile" -var="aws_region=$DeployRegion" random_id.bucket_suffix $randomSuffix 2>$null | Out-Null
                }
            }
            
            # Now destroy with proper state
            try {
                terraform destroy -auto-approve -var="aws_profile=$script:SelectedAwsProfile" -var="aws_region=$DeployRegion"
                Write-Success "Backend infrastructure destroyed"
            } catch {
                Write-Warning "Backend destruction failed, attempting manual cleanup..."
                Invoke-ManualBackendCleanup -BackendBucket $BackendBucket -BackendTable $BackendTable
            }
            
            Clear-LocalFiles
            
            Write-Success "All infrastructure and backend destroyed"
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "Backend resources not found or already clean"
    }
}

# Function for manual backend cleanup
function Invoke-ManualBackendCleanup {
    param(
        [string]$BackendBucket,
        [string]$BackendTable
    )
    
    if ($BackendBucket) {
        Write-Status "Attempting to empty and delete S3 bucket: $BackendBucket"
        aws s3 rm "s3://$BackendBucket" --recursive 2>$null | Out-Null
        aws s3 rb "s3://$BackendBucket" --force 2>$null | Out-Null
    }
    
    if ($BackendTable) {
        Write-Status "Attempting to delete DynamoDB table: $BackendTable"
        aws dynamodb delete-table --table-name $BackendTable 2>$null | Out-Null
    }
    
    Write-Warning "Manual cleanup attempted - some resources may still exist"
}

# Function to cleanup local files
function Clear-LocalFiles {
    Write-Status "Cleaning up local configuration files..."
    
    $filesToRemove = @(
        "backend-config.ps1",
        "environment\.terraform",
        "environment\terraform.tfstate",
        "environment\terraform.tfstate.backup",
        "environment\.terraform.lock.hcl",
        "backend-setup\.terraform",
        "backend-setup\terraform.tfstate",
        "backend-setup\terraform.tfstate.backup",
        "backend-setup\.terraform.lock.hcl"
    )
    
    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item $file -Recurse -Force -ErrorAction SilentlyContinue
            Write-Status "Removed: $file"
        }
    }
    
    Write-Success "Local files cleaned up"
}

# Parse command line arguments
param(
    [Parameter(Position=0)]
    [string]$Command = "deploy",
    
    [switch]$Redeploy,
    [switch]$SkipBedrockValidation,
    [switch]$Help
)

if ($Help) {
    Show-Help
    exit 0
}

$script:RedeployMode = $Redeploy
$script:SkipBedrockValidation = $SkipBedrockValidation

# Main script logic
switch ($Command.ToLower()) {
    "deploy" {
        if ($script:RedeployMode) {
            Write-Status "Starting AWS Health Dashboard redeployment (no prompts)..."
        } else {
            Write-Status "Starting AWS Health Dashboard deployment..."
        }
        
        Clear-EnvVars
        Test-Prerequisites
        Configure-Deployment
        
        if (-not $env:AWS_PROFILE -and (Test-Path "environment\terraform.tfvars")) {
            $content = Get-Content "environment\terraform.tfvars" -Raw
            if ($content -match 'aws_profile\s*=\s*"([^"]+)"') {
                $script:SelectedAwsProfile = $matches[1]
                $env:AWS_PROFILE = $script:SelectedAwsProfile
                Write-Status "Set AWS profile for operations: $script:SelectedAwsProfile"
            }
        }
        
        # Check Bedrock access for existing configurations in redeploy mode (after profile is set)
        if (-not $script:SkipBedrockValidation -and ($script:RedeployMode -or $script:UsingExistingConfig)) {
            Test-ExistingBedrockAccess
        } elseif ($script:SkipBedrockValidation) {
            Write-Warning "Skipping Bedrock validation for existing configuration (-SkipBedrockValidation flag used)"
        }
        
        Setup-Backend
        Deploy-Infrastructure
        Write-Success "Deployment complete!"
    }
    
    "destroy" {
        Write-Status "Starting AWS Health Dashboard destruction..."
        Setup-AwsProfile
        Remove-Infrastructure
    }
    
    "configure" {
        Write-Status "Starting AWS Health Dashboard configuration..."
        Configure-Deployment
        Write-Success "Configuration complete!"
    }
    
    default {
        Write-ErrorMsg "Unknown command: $Command"
        Write-Host ""
        Show-Help
        exit 1
    }
}
