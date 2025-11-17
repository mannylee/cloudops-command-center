#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    echo "AWS Health Dashboard Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  deploy      Deploy complete infrastructure (default)"
    echo "  --destroy   Destroy infrastructure with backend option"
    echo "  --configure Configure deployment settings only"
    echo ""
    echo "Options:"
    echo "  --redeploy, --no-prompts    Redeploy using existing configuration without prompts"
    echo "  --skip-bedrock-validation   Skip Bedrock model access validation (advanced users only)"
    echo "  --help, -h                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          Interactive deployment with full validation"
    echo "  $0 --redeploy              Redeploy with existing config and validation"
    echo "  $0 --destroy               Destroy infrastructure"
    echo "  $0 --configure             Configure deployment settings only"
    echo "  $0 --skip-bedrock-validation  Deploy without checking Bedrock model access"
    echo ""
    echo "Note: Skipping Bedrock validation may result in runtime errors if models are not accessible."
}

# Global variable to store the selected AWS profile
SELECTED_AWS_PROFILE=""

# Function to clean environment variables
clean_env_vars() {
    unset TF_BACKEND_BUCKET
    unset TF_BACKEND_TABLE
    unset AWS_PROFILE
}





# Function to setup AWS profile
setup_aws_profile() {
    # Check for existing config first (both redeploy mode and existing config)
    TFVARS_FILE="environment/terraform.tfvars"
    if [ -f "$TFVARS_FILE" ] && ([ "$REDEPLOY_MODE" = "true" ] || [ "$USING_EXISTING_CONFIG" = "true" ]); then
        SELECTED_AWS_PROFILE=$(grep 'aws_profile' "$TFVARS_FILE" | cut -d'"' -f2)
        if [ -z "$SELECTED_AWS_PROFILE" ]; then
            print_error "AWS profile not found in configuration"
            exit 1
        fi
        
        export AWS_PROFILE="$SELECTED_AWS_PROFILE"
        print_status "Using AWS profile from existing config: $SELECTED_AWS_PROFILE"
    else
        # Interactive mode
        PROFILES=($(aws configure list-profiles 2>/dev/null || echo "default"))
        
        if [ ${#PROFILES[@]} -eq 1 ]; then
            SELECTED_AWS_PROFILE="${PROFILES[0]}"
            print_status "Using AWS profile: $SELECTED_AWS_PROFILE"
        else
            print_status "Available AWS profiles:"
            for i in "${!PROFILES[@]}"; do
                echo "  $((i+1))) ${PROFILES[i]}"
            done
            
            while true; do
                read -p "Select profile (1-${#PROFILES[@]}): " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PROFILES[@]}" ]; then
                    SELECTED_AWS_PROFILE="${PROFILES[$((choice-1))]}"
                    break
                else
                    echo "Invalid choice. Please enter a number between 1 and ${#PROFILES[@]}."
                fi
            done
            print_status "Selected AWS profile: $SELECTED_AWS_PROFILE"
        fi
        
        export AWS_PROFILE="$SELECTED_AWS_PROFILE"
    fi
    
    # Test credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not working for profile: $SELECTED_AWS_PROFILE"
        print_error "Please configure AWS CLI properly"
        exit 1
    fi
    
    print_success "AWS credentials validated for profile: $SELECTED_AWS_PROFILE"
}

# Function to check for naming configuration changes
check_naming_changes() {
    local tfvars_file="$1"
    local new_prefix="$2"
    local new_suffix="$3"
    local new_random="$4"
    
    if [ ! -f "$tfvars_file" ]; then
        return 0  # No existing config, no changes to check
    fi
    
    # Extract current naming configuration from the naming_convention block
    local current_prefix=$(awk '/naming_convention = {/,/}/ { if ($1 == "prefix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
    local current_suffix=$(awk '/naming_convention = {/,/}/ { if ($1 == "suffix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
    local current_random=$(awk '/naming_convention = {/,/}/ { if ($1 == "use_random_suffix") { print $3 } }' "$tfvars_file" 2>/dev/null || echo "false")
    
    # Check if any naming configuration has changed
    if [ "$current_prefix" != "$new_prefix" ] || [ "$current_suffix" != "$new_suffix" ] || [ "$current_random" != "$new_random" ]; then
        echo ""
        print_warning "⚠️  NAMING CONFIGURATION CHANGE DETECTED ⚠️"
        echo "=================================="
        print_warning "Changing resource naming will force recreation of most AWS resources!"
        echo ""
        print_status "Current naming:"
        echo "  • Prefix: '$current_prefix'"
        echo "  • Suffix: '$current_suffix'"
        echo "  • Random suffix: $current_random"
        echo ""
        print_status "New naming:"
        echo "  • Prefix: '$new_prefix'"
        echo "  • Suffix: '$new_suffix'"
        echo "  • Random suffix: $new_random"
        echo ""
        print_warning "Resources that will be RECREATED (causing downtime):"
        echo "  • Lambda functions (event-processor, events-api)"
        echo "  • DynamoDB tables (all data will be lost)"
        echo "  • SQS queues"
        echo "  • API Gateway"
        echo "  • CloudWatch Log Groups"
        echo "  • IAM roles and policies"
        echo ""
        print_warning "This will result in:"
        echo "  • Temporary service downtime during recreation"
        echo "  • Loss of all stored health event data"
        echo "  • New API endpoints (frontend may need updates)"
        echo "=================================="
        echo ""
        print_status "Do you want to continue with these naming changes? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            print_status "Keeping existing naming configuration"
            return 1  # User chose to keep existing config
        fi
        echo ""
        print_status "Proceeding with naming changes..."
        return 0
    fi
    
    return 0  # No naming changes detected
}

# Function to detect environment from existing config
detect_environment() {
    # Check if environment config exists
    if [ -f "environment/terraform.tfvars" ]; then
        # Extract environment name from the config
        ENV_NAME=$(grep '^environment' environment/terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
        if [ -n "$ENV_NAME" ]; then
            print_status "Detected existing environment: $ENV_NAME"
        else
            ENV_NAME="dev"  # fallback
        fi
    else
        # No existing environment found
        ENV_NAME=""
    fi
}

# Function to configure deployment
configure_deployment() {
    # Skip configuration in redeploy mode
    if [ "$REDEPLOY_MODE" = "true" ]; then
        print_status "Using existing configuration (redeploy mode)"
        return
    fi
    
    print_status "Configuring deployment settings..."
    
    # Set the configuration file path
    TFVARS_FILE="environment/terraform.tfvars"
    
    # Check if terraform.tfvars already exists FIRST
    if [ -f "$TFVARS_FILE" ]; then
        print_warning "Configuration file already exists: $TFVARS_FILE"
        print_status "Current configuration:"
        echo "=================================="
        cat "$TFVARS_FILE"
        echo "=================================="
        
        # Extract and display health monitoring regions in a user-friendly way
        if grep -q "health_monitoring_regions" "$TFVARS_FILE"; then
            print_status "Health Monitoring Regions:"
            REGIONS_LINE=$(grep "health_monitoring_regions" "$TFVARS_FILE" | sed 's/.*= \[\(.*\)\]/\1/' | tr -d '"' | tr ',' '\n')
            echo "$REGIONS_LINE" | while read -r region; do
                region=$(echo "$region" | xargs)  # trim whitespace
                if [ -n "$region" ]; then
                    echo "  • $region"
                fi
            done
            echo "=================================="
        fi
        
        # Extract and display environment information
        if grep -q "environment" "$TFVARS_FILE"; then
            ENVIRONMENT_VALUE=$(grep '^environment' "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
            STAGE_VALUE=$(grep '^stage_name' "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
            print_status "Environment Configuration:"
            echo "  • Environment: $ENVIRONMENT_VALUE"
            echo "  • Stage: $STAGE_VALUE"
            echo "=================================="
        fi
        
        # Extract and display frontend build configuration
        if grep -q "build_and_upload" "$TFVARS_FILE"; then
            BUILD_UPLOAD_VALUE=$(grep "build_and_upload" "$TFVARS_FILE" | sed 's/.*= *\(.*\)/\1/' | xargs)
            print_status "Frontend Build & Upload:"
            if [ "$BUILD_UPLOAD_VALUE" = "true" ]; then
                echo "  • ✅ Enabled - Frontend will be built and uploaded automatically"
            else
                echo "  • ❌ Disabled - Frontend build/upload will be skipped"
            fi
            echo "=================================="
        fi
        
        # Extract and display email notification configuration
        if grep -q "enable_email_notifications" "$TFVARS_FILE"; then
            EMAIL_ENABLED=$(grep "^enable_email_notifications" "$TFVARS_FILE" | sed 's/.*= *\(.*\)/\1/' | xargs)
            print_status "Email Notifications:"
            if [ "$EMAIL_ENABLED" = "true" ]; then
                SENDER_EMAIL_VALUE=$(grep "^sender_email" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
                MASTER_EMAIL_VALUE=$(grep "^master_recipient_email" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
                SCHEDULE_VALUE=$(grep "^email_schedule_expression" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
                echo "  • ✅ Enabled - Weekly email summaries will be sent"
                echo "  • Sender: $SENDER_EMAIL_VALUE"
                echo "  • Recipient: $MASTER_EMAIL_VALUE"
                echo "  • Schedule: $SCHEDULE_VALUE"
            else
                echo "  • ❌ Disabled - No email notifications will be sent"
            fi
            echo "=================================="
        fi
        
        # Extract and display Bedrock model configuration
        if grep -q "bedrock_model_id" "$TFVARS_FILE"; then
            BEDROCK_MODEL_VALUE=$(grep "bedrock_model_id" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
            AWS_REGION_VALUE=$(grep "aws_region" "$TFVARS_FILE" | cut -d'"' -f2 2>/dev/null || echo "")
            print_status "Bedrock Model Configuration:"
            echo "  • Model ID: $BEDROCK_MODEL_VALUE"
            echo "  • Deployment Region: $AWS_REGION_VALUE"
            
            # Determine model name based on model ID
            case "$BEDROCK_MODEL_VALUE" in
                *"claude-sonnet-4-20250514-v1:0")
                    echo "  • Model Name: Claude Sonnet 4 (Latest)"
                    ;;
                *"claude-3-7-sonnet-20250219-v1:0")
                    echo "  • Model Name: Claude 3.7 Sonnet"
                    ;;
                *)
                    echo "  • Model Name: Custom/Unknown"
                    ;;
            esac
            
            # Show region prefix
            if [[ "$BEDROCK_MODEL_VALUE" == us.anthropic.* ]]; then
                echo "  • Region Prefix: us (US models)"
            elif [[ "$BEDROCK_MODEL_VALUE" == apac.anthropic.* ]]; then
                echo "  • Region Prefix: apac (Asia Pacific models)"
            else
                echo "  • Region Prefix: Unknown"
            fi
            echo "=================================="
        fi
        
        print_status "Do you want to reconfigure? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            print_status "Using existing configuration"
            # Set a flag to indicate we're using existing config
            USING_EXISTING_CONFIG="true"
            return
        fi
    fi
    
    # Setup AWS profile first for new/reconfigure
    if [ -z "$SELECTED_AWS_PROFILE" ]; then
        setup_aws_profile
    fi
    
    # Only prompt for environment name if we're configuring (new or reconfigure)
    print_status "Enter environment name (e.g., 'dev', 'staging', 'prod'):"
    read -r ENV_NAME
    while [ -z "$ENV_NAME" ]; do
        print_warning "Environment name is required"
        read -r ENV_NAME
    done
    
    print_success "Environment: $ENV_NAME"
    
    # Prompt for resource prefix
    print_status "Enter resource prefix (e.g., 'mycompany', 'acme') or press Enter for none:"
    read -r RESOURCE_PREFIX
    RESOURCE_PREFIX=${RESOURCE_PREFIX:-""}
    
    # Use environment name as suffix for consistent naming
    ENV_SUFFIX="$ENV_NAME"
    print_status "Using '$ENV_NAME' as resource naming suffix for consistency"
    
    # Prompt for random suffix
    print_status "Add random suffix for uniqueness? (y/N)"
    read -r RANDOM_SUFFIX
    if [[ "$RANDOM_SUFFIX" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        USE_RANDOM="true"
    else
        USE_RANDOM="false"
    fi
    
    # Prompt for deployment region
    configure_deployment_region
    
    # Ensure DEPLOYMENT_REGION is set
    if [ -z "$DEPLOYMENT_REGION" ]; then
        print_warning "No deployment region selected, using us-east-1 as default"
        DEPLOYMENT_REGION="us-east-1"
    fi
    print_status "Final deployment region: $DEPLOYMENT_REGION"
    
    # Check for naming configuration changes and warn user
    if ! check_naming_changes "$TFVARS_FILE" "$RESOURCE_PREFIX" "$ENV_SUFFIX" "$USE_RANDOM"; then
        # User chose to keep existing naming, extract current values
        RESOURCE_PREFIX=$(grep 'prefix.*=' "$TFVARS_FILE" | sed 's/.*prefix.*=.*"\(.*\)".*/\1/' 2>/dev/null || echo "")
        ENV_SUFFIX=$(grep 'suffix.*=' "$TFVARS_FILE" | sed 's/.*suffix.*=.*"\(.*\)".*/\1/' 2>/dev/null || echo "")
        USE_RANDOM=$(grep 'use_random_suffix.*=' "$TFVARS_FILE" | sed 's/.*use_random_suffix.*=.*\(true\|false\).*/\1/' 2>/dev/null || echo "false")
        print_status "Using existing naming configuration"
    fi
    
    # Validate bucket naming before proceeding
    if ! validate_bucket_naming "$RESOURCE_PREFIX" "$ENV_SUFFIX" "$USE_RANDOM"; then
        print_error "Bucket naming validation failed. Please reconfigure."
        exit 1
    fi
    

    
    # Create terraform.tfvars
    print_status "Creating configuration file..."
    cat > "$TFVARS_FILE" << EOF
# AWS Health Dashboard Configuration
aws_region    = "$DEPLOYMENT_REGION"
aws_profile   = "$SELECTED_AWS_PROFILE"
stage_name    = "$ENV_NAME"
environment   = "$ENV_NAME"
project_name  = "health-dashboard"
react_app_domain = "localhost:3000"

# Resource Naming Convention
naming_convention = {
  prefix    = "$RESOURCE_PREFIX"
  suffix    = "$ENV_SUFFIX"
  separator = "-"
  use_random_suffix = $USE_RANDOM
}
EOF
    
    print_success "Configuration saved to $TFVARS_FILE"
    
    # Configure health monitoring regions
    configure_health_monitoring_regions
    
    # Configure frontend build and upload
    configure_frontend_build_upload
    
    # Configure Bedrock model selection
    configure_bedrock_model
    
    # Configure DynamoDB TTL
    configure_dynamodb_ttl
    
    # Configure email notifications
    configure_email_notifications
    
    # Show preview of resource names
    if [ -n "$RESOURCE_PREFIX" ] || [ -n "$ENV_SUFFIX" ] || [ "$USE_RANDOM" = "true" ]; then
        print_status "Resource naming preview:"
        NAME_PARTS="health-dashboard"
        [ -n "$RESOURCE_PREFIX" ] && NAME_PARTS="$RESOURCE_PREFIX-$NAME_PARTS"
        [ -n "$ENV_SUFFIX" ] && NAME_PARTS="$NAME_PARTS-$ENV_SUFFIX"
        [ "$USE_RANDOM" = "true" ] && NAME_PARTS="$NAME_PARTS-[random]"
        echo "  Example: $NAME_PARTS-lambda-function"
    fi
}

# Function to configure deployment region
configure_deployment_region() {
    print_status ""
    print_status "=== Deployment Region Selection ==="
    print_status "Select the AWS region where infrastructure will be deployed."
    print_status "Note: AWS Health API will always use us-east-1 regardless of deployment region."
    print_status ""
    
    # Define available regions for deployment (limited to us-east-1 and ap-southeast-1)
    DEPLOY_REGIONS=("us-east-1" "ap-southeast-1")
    DEPLOY_DESCRIPTIONS=("US East (N. Virginia) - Uses us.anthropic.* Bedrock models" "Asia Pacific (Singapore) - Uses apac.anthropic.* Bedrock models")
    
    print_status "Available deployment regions:"
    for i in "${!DEPLOY_REGIONS[@]}"; do
        region="${DEPLOY_REGIONS[i]}"
        description="${DEPLOY_DESCRIPTIONS[i]}"
        echo "  $((i+1))) $region - $description"
    done
    
    echo ""
    while true; do
        read -p "Select deployment region (1-${#DEPLOY_REGIONS[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#DEPLOY_REGIONS[@]}" ]; then
            DEPLOYMENT_REGION="${DEPLOY_REGIONS[$((choice-1))]}"
            print_success "Selected deployment region: $DEPLOYMENT_REGION"
            
            # Set region-specific Bedrock model prefix for later use
            if [ "$DEPLOYMENT_REGION" = "us-east-1" ]; then
                BEDROCK_REGION_PREFIX="us"
            elif [ "$DEPLOYMENT_REGION" = "ap-southeast-1" ]; then
                BEDROCK_REGION_PREFIX="apac"
            fi
            
            print_status "Bedrock models will use '$BEDROCK_REGION_PREFIX.anthropic.*' prefix"
            break
        else
            print_warning "Invalid choice. Please enter a number between 1 and ${#DEPLOY_REGIONS[@]}."
        fi
    done
}

# Function to configure health monitoring regions
configure_health_monitoring_regions() {
    print_status ""
    print_status "=== AWS Health Event Monitoring Configuration ==="
    print_status "Select regions to monitor for AWS Health events."
    print_status "Note: us-east-1 is always included as the processing region."
    print_status ""
    
    # Define available regions with descriptions (using parallel arrays for compatibility)
    REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-south-1" "ca-central-1" "sa-east-1")
    DESCRIPTIONS=("US East (N. Virginia)" "US East (Ohio)" "US West (N. California)" "US West (Oregon)" "Europe (Ireland)" "Europe (London)" "Europe (Paris)" "Europe (Frankfurt)" "Europe (Stockholm)" "Asia Pacific (Singapore)" "Asia Pacific (Sydney)" "Asia Pacific (Tokyo)" "Asia Pacific (Seoul)" "Asia Pacific (Osaka)" "Asia Pacific (Mumbai)" "Canada (Central)" "South America (São Paulo)")
    
    print_status "Available regions:"
    for i in "${!REGIONS[@]}"; do
        region="${REGIONS[i]}"
        description="${DESCRIPTIONS[i]}"
        if [ "$region" = "us-east-1" ]; then
            echo "  $((i+1))) $region - $description (always included)"
        else
            echo "  $((i+1))) $region - $description"
        fi
    done
    
    echo ""
    echo "  $((${#REGIONS[@]}+1))) All regions"
    echo "  $((${#REGIONS[@]}+2))) Common regions (us-east-1, us-west-2, eu-west-1)"
    echo "  $((${#REGIONS[@]}+3))) US regions only"
    echo "  $((${#REGIONS[@]}+4))) EU regions only"
    echo "  $((${#REGIONS[@]}+5))) Custom selection"
    echo "  $((${#REGIONS[@]}+6))) Skip (us-east-1 only)"
    
    print_status ""
    read -p "Select option (1-$((${#REGIONS[@]}+6))): " choice
    
    SELECTED_REGIONS=("us-east-1")  # Always include us-east-1
    
    case $choice in
        $((${#REGIONS[@]}+1)))
            # All regions
            SELECTED_REGIONS=("${REGIONS[@]}")
            print_status "Selected: All regions"
            ;;
        $((${#REGIONS[@]}+2)))
            # Common regions
            SELECTED_REGIONS=("us-east-1" "us-west-2" "eu-west-1")
            print_status "Selected: Common regions (us-east-1, us-west-2, eu-west-1)"
            ;;
        $((${#REGIONS[@]}+3)))
            # US regions only
            SELECTED_REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2")
            print_status "Selected: US regions only"
            ;;
        $((${#REGIONS[@]}+4)))
            # EU regions only
            SELECTED_REGIONS=("us-east-1" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1")
            print_status "Selected: EU regions (plus us-east-1 for processing)"
            ;;
        $((${#REGIONS[@]}+5)))
            # Custom selection
            print_status "Custom selection mode:"
            print_status "Enter region numbers separated by spaces (e.g., 1 4 5):"
            print_status "us-east-1 is automatically included."
            read -r custom_choices
            
            SELECTED_REGIONS=("us-east-1")
            for num in $custom_choices; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#REGIONS[@]}" ]; then
                    region="${REGIONS[$((num-1))]}"
                    if [ "$region" != "us-east-1" ]; then
                        SELECTED_REGIONS+=("$region")
                    fi
                fi
            done
            
            # Remove duplicates
            SELECTED_REGIONS=($(printf "%s\n" "${SELECTED_REGIONS[@]}" | sort -u))
            print_status "Selected regions: ${SELECTED_REGIONS[*]}"
            ;;
        $((${#REGIONS[@]}+6)))
            # Skip - us-east-1 only
            SELECTED_REGIONS=("us-east-1")
            print_status "Selected: us-east-1 only"
            ;;
        *)
            # Single region selection
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#REGIONS[@]}" ]; then
                selected_region="${REGIONS[$((choice-1))]}"
                if [ "$selected_region" != "us-east-1" ]; then
                    SELECTED_REGIONS+=("$selected_region")
                fi
                print_status "Selected: ${SELECTED_REGIONS[*]}"
            else
                print_warning "Invalid choice. Using us-east-1 only."
                SELECTED_REGIONS=("us-east-1")
            fi
            ;;
    esac
    
    # Validate AWS Health API access (Health API is primarily in us-east-1 for org events)
    print_status "Validating AWS Health API access..."
    VALID_REGIONS=()
    
    # Test Health API access in us-east-1 first
    if aws health describe-events --region us-east-1 --max-items 1 >/dev/null 2>&1; then
        print_status "AWS Health API access confirmed"
        # All selected regions are valid for EventBridge rules, even if Health API isn't directly accessible
        VALID_REGIONS=("${SELECTED_REGIONS[@]}")
        print_status "All selected regions will be configured for EventBridge health event monitoring"
    else
        print_warning "AWS Health API access test failed. This might be due to:"
        print_warning "1. Organization Health Dashboard not enabled"
        print_warning "2. Insufficient permissions"
        print_warning "3. No AWS Business/Enterprise support plan"
        print_status "Proceeding with selected regions - EventBridge rules will still be created"
        VALID_REGIONS=("${SELECTED_REGIONS[@]}")
    fi
    
    if [ ${#VALID_REGIONS[@]} -eq 0 ]; then
        print_error "No valid regions found. Please check your AWS permissions."
        exit 1
    fi
    
    SELECTED_REGIONS=("${VALID_REGIONS[@]}")
    print_success "Validated regions: ${SELECTED_REGIONS[*]}"
    
    # Convert array to Terraform list format
    TERRAFORM_REGIONS="["
    for i in "${!SELECTED_REGIONS[@]}"; do
        if [ $i -gt 0 ]; then
            TERRAFORM_REGIONS+=", "
        fi
        TERRAFORM_REGIONS+="\"${SELECTED_REGIONS[i]}\""
    done
    TERRAFORM_REGIONS+="]"
    
    # Append to terraform.tfvars
    cat >> "$TFVARS_FILE" << EOF

# Health Event Monitoring Regions
health_monitoring_regions = $TERRAFORM_REGIONS
EOF
    
    print_success "Health monitoring regions configured: ${SELECTED_REGIONS[*]}"
}

# Function to configure frontend build and upload
configure_frontend_build_upload() {
    print_status ""
    print_status "=== Frontend Build and Upload Configuration ==="
    print_status "Configure whether to automatically build and deploy the React frontend to S3."
    print_status ""
    
    print_status "Options:"
    echo "  1) Yes - Build and upload frontend automatically during deployment"
    echo "  2) No  - Skip frontend build/upload (manual deployment required)"
    echo ""
    
    while true; do
        read -p "Build and upload frontend automatically? (Y/n): " choice
        case $choice in
            [Yy]* | "" )
                BUILD_AND_UPLOAD="true"
                print_success "Frontend will be built and uploaded automatically"
                break
                ;;
            [Nn]* )
                BUILD_AND_UPLOAD="false"
                print_status "Frontend build/upload will be skipped"
                break
                ;;
            * )
                print_warning "Please answer yes (y) or no (n)"
                ;;
        esac
    done
    
    # Append to terraform.tfvars
    cat >> "$TFVARS_FILE" << EOF

# Frontend Build and Upload Configuration
build_and_upload = $BUILD_AND_UPLOAD
EOF
    
    print_success "Frontend configuration saved"
}

# Function to validate bucket naming
validate_bucket_naming() {
    local prefix="$1"
    local suffix="$2"
    local use_random="$3"
    
    # Calculate the potential bucket name length
    # Format: {prefix}-health-dashboard-{suffix}-{random}-backend-terraform-state-{8-char-hex}
    local base_name="health-dashboard"
    local backend_suffix="backend-terraform-state"
    local random_hex_length=8  # 8 character hex string
    
    local total_length=0
    
    # Add prefix if provided
    if [ -n "$prefix" ]; then
        total_length=$((total_length + ${#prefix} + 1))  # +1 for separator
    fi
    
    # Add base name
    total_length=$((total_length + ${#base_name} + 1))  # +1 for separator
    
    # Add suffix if provided
    if [ -n "$suffix" ]; then
        total_length=$((total_length + ${#suffix} + 1))  # +1 for separator
    fi
    
    # Add random suffix if enabled
    if [ "$use_random" = "true" ]; then
        total_length=$((total_length + 8 + 1))  # 8 chars + separator
    fi
    
    # Add backend suffix
    total_length=$((total_length + ${#backend_suffix} + 1))  # +1 for separator
    
    # Add final random hex
    total_length=$((total_length + random_hex_length))
    
    # S3 bucket name limit is 63 characters
    if [ $total_length -gt 63 ]; then
        echo ""
        print_error "⚠️  BUCKET NAME TOO LONG ⚠️"
        echo "=================================="
        print_error "The generated S3 bucket name will be $total_length characters (limit: 63)"
        echo ""
        print_status "Current naming configuration:"
        echo "  • Prefix: '$prefix' (${#prefix} chars)"
        echo "  • Base: '$base_name' (${#base_name} chars)"
        echo "  • Suffix: '$suffix' (${#suffix} chars)"
        echo "  • Random suffix: $use_random"
        echo "  • Backend suffix: '$backend_suffix' (${#backend_suffix} chars)"
        echo "  • Final random: 8 chars"
        echo ""
        print_status "Suggestions to fix:"
        echo "  1. Use shorter prefix (current: ${#prefix} chars)"
        echo "  2. Use shorter suffix (current: ${#suffix} chars)"
        echo "  3. Disable random suffix if not needed"
        echo ""
        print_error "Please reconfigure with shorter names"
        echo "=================================="
        return 1
    fi
    
    print_success "Bucket naming validation passed ($total_length/63 characters)"
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install and configure AWS CLI"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to list available Bedrock models (for troubleshooting)
list_available_bedrock_models() {
    local deployment_region="$1"
    
    print_status "Checking available Bedrock models in region: $deployment_region"
    
    if aws bedrock list-foundation-models --region "$deployment_region" --output table --query 'modelSummaries[?contains(modelId, `anthropic`)].{ModelId:modelId,ModelName:modelName,Status:modelLifecycle.status}' 2>/dev/null; then
        echo ""
        print_status "To enable model access, visit: https://console.aws.amazon.com/bedrock/home?region=$deployment_region#/modelaccess"
    else
        print_warning "Could not list Bedrock models. This might be due to insufficient permissions."
    fi
}

# Function to validate Bedrock model access
validate_bedrock_access() {
    local deployment_region="$1"
    local bedrock_model_id="$2"
    
    print_status "Validating Bedrock model access..."
    print_status "Checking access to model: $bedrock_model_id in region: $deployment_region"
    
    # Test if we can invoke the specific Bedrock model
    local test_payload='{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}'
    
    # Try to invoke the model with a minimal test
    if aws bedrock-runtime invoke-model \
        --region "$deployment_region" \
        --model-id "$bedrock_model_id" \
        --body "$test_payload" \
        --cli-binary-format raw-in-base64-out \
        /tmp/bedrock_test_output.json >/dev/null 2>&1; then
        
        print_success "Bedrock model access validated: $bedrock_model_id"
        rm -f /tmp/bedrock_test_output.json
        return 0
    else
        print_error "❌ Bedrock model access validation failed!"
        print_error "Model: $bedrock_model_id"
        print_error "Region: $deployment_region"
        echo ""
        
        # Show available models for troubleshooting
        list_available_bedrock_models "$deployment_region"
        echo ""
        
        print_status "🔧 To fix this issue:"
        echo "1. Go to AWS Console → Amazon Bedrock → Model access"
        echo "2. Navigate to the '$deployment_region' region"
        echo "3. Request access to the following models:"
        
        # Show region-specific models that need to be enabled
        if [ "$deployment_region" = "us-east-1" ]; then
            echo "   • Claude Sonnet 4 (us.anthropic.claude-sonnet-4-20250514-v1:0)"
            echo "   • Claude 3.7 Sonnet (us.anthropic.claude-3-7-sonnet-20250219-v1:0)"
        elif [ "$deployment_region" = "ap-southeast-1" ]; then
            echo "   • Claude Sonnet 4 (apac.anthropic.claude-sonnet-4-20250514-v1:0)"
            echo "   • Claude 3.7 Sonnet (apac.anthropic.claude-3-7-sonnet-20250219-v1:0)"
        fi
        
        echo "4. Wait for approval (usually instant for Claude models)"
        echo "5. Re-run this deployment script"
        echo ""
        print_status "📖 More info: https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html"
        
        rm -f /tmp/bedrock_test_output.json
        return 1
    fi
}

# Function to check Bedrock access for existing configuration
check_existing_bedrock_access() {
    local tfvars_file="environment/terraform.tfvars"
    
    if [ -f "$tfvars_file" ]; then
        # Extract deployment region and bedrock model from existing config
        local existing_region=$(grep 'aws_region' "$tfvars_file" | cut -d'"' -f2 2>/dev/null || echo "")
        local existing_model=$(grep 'bedrock_model_id' "$tfvars_file" | cut -d'"' -f2 2>/dev/null || echo "")
        
        if [ -n "$existing_region" ] && [ -n "$existing_model" ]; then
            print_status "Found existing Bedrock configuration:"
            print_status "  Region: $existing_region"
            print_status "  Model: $existing_model"
            
            if ! validate_bedrock_access "$existing_region" "$existing_model"; then
                print_error "Existing Bedrock model configuration is not accessible"
                print_status "Please enable model access or reconfigure with a different model"
                exit 1
            fi
        fi
    fi
}

# Function to setup backend
setup_backend() {
    print_status "Setting up Terraform backend (S3 + DynamoDB)..."
    
    # Verify credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials failed"
        exit 1
    fi
    
    cd backend-setup || {
        print_error "Failed to change to backend-setup directory"
        exit 1
    }
    
    # Initialize terraform
    terraform init -upgrade
    
    if [ ! -f "terraform.tfstate" ]; then
        print_status "Initializing backend terraform..."
        if ! terraform init; then
            print_error "Backend terraform init failed"
            cd ..
            exit 1
        fi
        
        print_status "Creating backend resources..."
        # Create backend-specific variables file (only what backend setup needs)
        if [ -f "../environment/terraform.tfvars" ]; then
            # Extract values from main config
            AWS_REGION_VALUE=$(grep 'aws_region' ../environment/terraform.tfvars | cut -d'"' -f2)
            PROJECT_NAME_VALUE=$(grep 'project_name' ../environment/terraform.tfvars | cut -d'"' -f2)
            
            # Extract naming convention components
            PREFIX_VALUE=$(awk '/naming_convention = {/,/}/ { if ($1 == "prefix") { gsub(/[",]/, "", $3); print $3 } }' ../environment/terraform.tfvars)
            SUFFIX_VALUE=$(awk '/naming_convention = {/,/}/ { if ($1 == "suffix") { gsub(/[",]/, "", $3); print $3 } }' ../environment/terraform.tfvars)
            USE_RANDOM_VALUE=$(awk '/naming_convention = {/,/}/ { if ($1 == "use_random_suffix") { print $3 } }' ../environment/terraform.tfvars)
            
            cat > temp_backend_vars.tfvars << EOF
aws_region = "$AWS_REGION_VALUE"
project_name = "$PROJECT_NAME_VALUE"
naming_convention = {
  prefix    = "$PREFIX_VALUE"
  suffix    = "$SUFFIX_VALUE"
  separator = "-"
  use_random_suffix = ${USE_RANDOM_VALUE:-false}
}
EOF
        else
            # Create temporary vars with current values
            cat > temp_backend_vars.tfvars << EOF
aws_region = "${DEPLOYMENT_REGION:-us-east-1}"
project_name = "health-dashboard"
naming_convention = {
  prefix    = "${RESOURCE_PREFIX:-}"
  suffix    = "${ENV_SUFFIX:-}"
  separator = "-"
  use_random_suffix = ${USE_RANDOM:-false}
}
EOF
        fi
        BACKEND_VARS="-var-file=temp_backend_vars.tfvars"
        
        if ! terraform apply -auto-approve -var="aws_profile=$SELECTED_AWS_PROFILE" $BACKEND_VARS; then
            print_error "Backend terraform apply failed"
            # Clean up temporary file if it exists
            [ -f "temp_backend_vars.tfvars" ] && rm -f "temp_backend_vars.tfvars"
            cd ..
            exit 1
        fi
        
        # Clean up temporary file if it exists
        [ -f "temp_backend_vars.tfvars" ] && rm -f "temp_backend_vars.tfvars"
        
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
        DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name 2>/dev/null)
        BACKEND_RANDOM_SUFFIX=$(terraform output -raw random_suffix 2>/dev/null)
        
        if [ -z "$S3_BUCKET" ] || [ -z "$DYNAMODB_TABLE" ]; then
            print_error "Failed to get backend outputs"
            cd ..
            exit 1
        fi
        
        print_success "Backend setup complete"
        print_status "S3 Bucket: $S3_BUCKET"
        print_status "DynamoDB Table: $DYNAMODB_TABLE"
        
        # Store backend configuration for later use
        echo "export TF_BACKEND_BUCKET='$S3_BUCKET'" > ../backend-config.sh
        echo "export TF_BACKEND_TABLE='$DYNAMODB_TABLE'" >> ../backend-config.sh
        echo "export TF_BACKEND_RANDOM_SUFFIX='$BACKEND_RANDOM_SUFFIX'" >> ../backend-config.sh
        
        print_success "Backend configuration stored"
    else
        # Backend exists, get the configuration
        print_status "Backend already exists, retrieving configuration..."
        # Ensure terraform is initialized before getting outputs
        terraform init -upgrade
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
        DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name 2>/dev/null)
        BACKEND_RANDOM_SUFFIX=$(terraform output -raw random_suffix 2>/dev/null)
        
        if [ -n "$S3_BUCKET" ] && [ -n "$DYNAMODB_TABLE" ]; then
            echo "export TF_BACKEND_BUCKET='$S3_BUCKET'" > ../backend-config.sh
            echo "export TF_BACKEND_TABLE='$DYNAMODB_TABLE'" >> ../backend-config.sh
            echo "export TF_BACKEND_RANDOM_SUFFIX='$BACKEND_RANDOM_SUFFIX'" >> ../backend-config.sh
            print_success "Using existing backend configuration"
            print_status "S3 Bucket: $S3_BUCKET"
            print_status "DynamoDB Table: $DYNAMODB_TABLE"
        else
            print_error "Backend exists but configuration not readable. Please run './deploy.sh cleanup' and try again."
            cd ..
            exit 1
        fi
    fi
    
    cd .. || {
        print_error "Failed to return to main directory"
        exit 1
    }
}

# Function to build and upload frontend if enabled
build_and_upload_frontend() {
    local tfvars_file="terraform.tfvars"
    
    print_status "Checking frontend build configuration..."
    
    # Check if build_and_upload is enabled
    if [ -f "$tfvars_file" ]; then
        BUILD_UPLOAD_VALUE=$(grep "build_and_upload" "$tfvars_file" | sed 's/.*= *\(.*\)/\1/' | xargs 2>/dev/null || echo "false")
        print_status "Found build_and_upload = $BUILD_UPLOAD_VALUE"
        
        if [ "$BUILD_UPLOAD_VALUE" = "true" ]; then
            print_status "Building and uploading React frontend..."
            
            # Get frontend bucket name from Terraform output
            FRONTEND_BUCKET=$(terraform output -json frontend_config 2>/dev/null | jq -r '.s3_bucket_name' 2>/dev/null || echo "")
            CLOUDFRONT_ID=$(terraform output -json frontend_config 2>/dev/null | jq -r '.cloudfront_distribution_id' 2>/dev/null || echo "")
            
            print_status "Frontend bucket: $FRONTEND_BUCKET"
            print_status "CloudFront ID: $CLOUDFRONT_ID"
            
            if [ -n "$FRONTEND_BUCKET" ]; then
                # Build React app
                print_status "Building React application..."
                cd ../../frontend/app
                
                if [ ! -f "package.json" ]; then
                    print_error "Frontend package.json not found at $(pwd)"
                    cd ../../backend/environment
                    return 1
                fi
                
                print_status "Installing npm dependencies..."
                npm install
                print_status "Building React app..."
                npm run build
                
                # Upload to S3
                print_status "Uploading to S3 bucket: $FRONTEND_BUCKET"
                aws s3 sync dist/ s3://$FRONTEND_BUCKET/ --delete
                
                # Invalidate CloudFront cache
                if [ -n "$CLOUDFRONT_ID" ]; then
                    print_status "Invalidating CloudFront cache: $CLOUDFRONT_ID"
                    aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*" >/dev/null
                    print_success "CloudFront cache invalidated"
                fi
                
                cd ../../backend/environment
                print_success "Frontend build and upload completed"
            else
                print_warning "Frontend bucket name not found - checking Terraform outputs..."
                terraform output
            fi
        else
            print_status "Frontend build disabled (build_and_upload = $BUILD_UPLOAD_VALUE)"
        fi
    else
        print_warning "terraform.tfvars file not found at $(pwd)/$tfvars_file"
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying main infrastructure..."
    
    # Verify credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials failed"
        exit 1
    fi
    
    cd environment
    
    # Load backend configuration
    if [ -f "../backend-config.sh" ]; then
        source ../backend-config.sh
        print_status "Using backend configuration: $TF_BACKEND_BUCKET"
    elif [ -f "../../backend-setup/terraform.tfstate" ]; then
        # Backend exists but config file missing, recreate it
        cd ../../backend-setup
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
        DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name 2>/dev/null)
        BACKEND_RANDOM_SUFFIX=$(terraform output -raw random_suffix 2>/dev/null)
        if [ -n "$S3_BUCKET" ] && [ -n "$DYNAMODB_TABLE" ]; then
            echo "export TF_BACKEND_BUCKET='$S3_BUCKET'" > ../backend-config.sh
            echo "export TF_BACKEND_TABLE='$DYNAMODB_TABLE'" >> ../backend-config.sh
            echo "export TF_BACKEND_RANDOM_SUFFIX='$BACKEND_RANDOM_SUFFIX'" >> ../backend-config.sh
            source ../backend-config.sh
            print_status "Using existing backend configuration"
        else
            print_error "Backend exists but outputs not available. Please run './deploy.sh cleanup' and try again."
            exit 1
        fi
        cd ../environment
    else
        print_error "Backend not found. This should not happen as setup_backend runs first."
        exit 1
    fi
    
    # Get deployment region from tfvars
    DEPLOY_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
    
    terraform init -backend-config="bucket=$TF_BACKEND_BUCKET" \
                  -backend-config="key=environment/terraform.tfstate" \
                  -backend-config="region=$DEPLOY_REGION" \
                  -migrate-state
    
    terraform plan -var="s3_backend_bucket=$TF_BACKEND_BUCKET" \
                   -var="dynamodb_backend_table=$TF_BACKEND_TABLE" \
                   -var="backend_random_suffix=$TF_BACKEND_RANDOM_SUFFIX" \
                   -out=tfplan
    
    if [ "$REDEPLOY_MODE" = "true" ]; then
        print_status "Auto-applying changes (redeploy mode)..."
        terraform apply -auto-approve tfplan
        rm tfplan
    else
        print_status "Review the plan above. Do you want to continue? (y/N)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            terraform apply tfplan
            rm tfplan
        else
            print_warning "Deployment cancelled"
            rm tfplan
            exit 0
        fi
    fi
        
    print_success "Infrastructure deployed successfully!"
    
    # Build and upload frontend after infrastructure deployment
    build_and_upload_frontend
    
    # Check if this is an initial deployment or a redeployment
    INITIAL_DEPLOYMENT=false
    
    # Check for a marker file that indicates previous deployment
    if [ ! -f ".deployment_marker" ]; then
        INITIAL_DEPLOYMENT=true
        # Create marker file for future runs
        touch .deployment_marker
        print_status "Initial deployment detected"
    else
        print_status "Redeployment detected - skipping Lambda invocation"
    fi
    
    # Only trigger Lambda function on initial deployment
    if [ "$INITIAL_DEPLOYMENT" = true ]; then
        print_status "Triggering initial health events collection..."
        
        # Get the deployment region from terraform.tfvars
        DEPLOYMENT_REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
        print_status "Using deployment region: $DEPLOYMENT_REGION"
        
        EVENT_PROCESSOR_NAME=$(terraform output -raw event_processor_function_name 2>/dev/null)
        if [ -n "$EVENT_PROCESSOR_NAME" ]; then
            print_status "Invoking function asynchronously: $EVENT_PROCESSOR_NAME"
            if aws lambda invoke --region "$DEPLOYMENT_REGION" --function-name "$EVENT_PROCESSOR_NAME" --invocation-type Event --payload '{}' /tmp/lambda-response.json 2>/tmp/lambda-error.log; then
                print_success "Initial health events collection triggered successfully"
                print_status "Monitoring execution progress..."
                
                # Monitor function completion
                print_status "Waiting for function to complete (checking every 30 seconds)..."
                for i in {1..30}; do  # 15 minutes max (30 * 30 seconds = 900 seconds = 15 minutes)
                    echo -n "."
                    
                    # Calculate start time (5 minutes ago)
                    START_TIME=$(( ($(date +%s) - 300) * 1000 ))
                    
                    # Get the latest log stream
                    LATEST_LOG_STREAM=$(aws logs describe-log-streams --region "$DEPLOYMENT_REGION" --log-group-name "/aws/lambda/$EVENT_PROCESSOR_NAME" --order-by LastEventTime --descending --limit 1 --query 'logStreams[0].logStreamName' --output text 2>/dev/null)

                    # Check for completion messages in the latest stream
                    if [ -n "$LATEST_LOG_STREAM" ] && [ "$LATEST_LOG_STREAM" != "None" ]; then
                        LOG_FILTER_RESULT=$(aws logs filter-log-events --region "$DEPLOYMENT_REGION" --log-group-name "/aws/lambda/$EVENT_PROCESSOR_NAME" --log-stream-names "$LATEST_LOG_STREAM" --start-time "$START_TIME" --filter-pattern "END" --query 'events[0].message' --output text 2>/dev/null)
                    else
                        LOG_FILTER_RESULT="No log stream found"
                    fi
                    
                    if echo "$LOG_FILTER_RESULT" | grep -q "END RequestId"; then
                        echo
                        print_success "Event processor execution completed"
                        break
                    fi
                    
                    if [ $i -eq 30 ]; then
                        echo
                        print_warning "Function may still be running - continuing with deployment"
                        print_status "Check CloudWatch logs: /aws/lambda/$EVENT_PROCESSOR_NAME"
                        break
                    fi

                    sleep 30
                done
                
                # Add completion message for Lambda monitoring
                print_status "Lambda monitoring process completed"
            else
                print_warning "Failed to invoke Lambda function - events will be collected on next scheduled run"
            fi
            rm -f /tmp/lambda-response.json 2>/dev/null || true
        else
            print_warning "Event processor function name not found - skipping initial trigger"
        fi
        
        # Add final acknowledgment for the Lambda invocation process
        print_success "Initial data collection process completed"
    fi
    
    # Check if frontend is enabled
    BUILD_AND_UPLOAD=$(grep "^build_and_upload" terraform.tfvars 2>/dev/null | sed 's/.*= *\(.*\)/\1/' | xargs)
    
    if [ "$BUILD_AND_UPLOAD" = "true" ]; then
        print_status "Your React app:"
        echo "=================================="
        terraform output frontend_config 2>/dev/null || echo "Frontend config not available"
        echo "=================================="
    else
        print_status "S3 Bucket (for email attachments):"
        echo "=================================="
        BUCKET_NAME=$(terraform output -json frontend_config 2>/dev/null | jq -r '.s3_bucket_name' 2>/dev/null || echo "")
        if [ -n "$BUCKET_NAME" ]; then
            echo "s3_bucket_name = \"$BUCKET_NAME\""
            echo ""
            echo "Note: Frontend (CloudFront/API Gateway) not deployed (build_and_upload = false)"
            echo "      S3 bucket is used for email attachments only"
        else
            echo "S3 bucket not available"
        fi
        echo "=================================="
    fi
    
    cd ../..
}

# Function to check if resources are actually destroyed
check_resources_destroyed() {
    print_status "Verifying main infrastructure resource destruction..."
    print_status "(Note: Backend storage resources are checked separately)"
    
    # Check for main infrastructure resources that should be gone
    local resources_exist=false
    
    # Try to determine the naming pattern from terraform.tfvars
    local name_pattern="health-dashboard"  # Default fallback
    local tfvars_file="terraform.tfvars"
    
    if [ -f "$tfvars_file" ]; then
        # Extract project name
        local project_name=$(grep 'project_name' "$tfvars_file" | cut -d'"' -f2 2>/dev/null || echo "health-dashboard")
        
        # Extract naming convention components
        local prefix=$(awk '/naming_convention = {/,/}/ { if ($1 == "prefix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
        local suffix=$(awk '/naming_convention = {/,/}/ { if ($1 == "suffix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
        
        # Build the expected name pattern
        name_pattern="$project_name"
        if [ -n "$prefix" ]; then
            name_pattern="$prefix-$name_pattern"
        fi
        if [ -n "$suffix" ]; then
            name_pattern="$name_pattern-$suffix"
        fi
        
        print_status "Looking for resources with pattern: $name_pattern"
    else
        print_warning "terraform.tfvars not found, using default pattern: $name_pattern"
    fi
    
    # Check Lambda functions (excluding any potential backend-related functions)
    local lambda_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '$name_pattern')].[FunctionName]" --output text 2>/dev/null | grep -v "backend\|terraform" || true)
    if [ -n "$lambda_functions" ]; then
        print_warning "Main infrastructure Lambda functions still exist: $lambda_functions"
        resources_exist=true
    fi
    
    # Check DynamoDB tables (only main infrastructure tables, excluding backend storage)
    local all_tables=$(aws dynamodb list-tables --query "TableNames" --output text 2>/dev/null || true)
    local main_infra_tables=""
    
    # Look specifically for main infrastructure tables (events, filters, counts)
    for table in $all_tables; do
        if [[ "$table" =~ $name_pattern.*(events|filters|counts)$ ]] && [[ ! "$table" =~ backend ]]; then
            if [ -z "$main_infra_tables" ]; then
                main_infra_tables="$table"
            else
                main_infra_tables="$main_infra_tables $table"
            fi
        fi
    done
    
    if [ -n "$main_infra_tables" ]; then
        print_warning "Main infrastructure DynamoDB tables still exist: $main_infra_tables"
        resources_exist=true
    fi
    
    # Check API Gateway
    if aws apigateway get-rest-apis --query "items[?contains(name, '$name_pattern')]" --output text 2>/dev/null | grep -q .; then
        print_warning "API Gateway still exists"
        resources_exist=true
    fi
    
    # Check S3 buckets (frontend bucket, excluding backend buckets)
    local s3_buckets=$(aws s3 ls | grep "$name_pattern" | grep -v "backend\|terraform" | awk '{print $3}' || true)
    if [ -n "$s3_buckets" ]; then
        print_warning "Main infrastructure S3 buckets still exist: $s3_buckets"
        resources_exist=true
    fi
    
    if [ "$resources_exist" = true ]; then
        return 1  # Main infrastructure resources still exist
    else
        print_success "Main infrastructure destruction verified (backend storage preserved)"
        return 0  # Main infrastructure resources are gone
    fi
}

# Function to perform robust destroy with retry logic
destroy_with_retry() {
    local max_attempts=3
    local attempt=1
    local destroy_success=false
    
    # Check if we have a valid terraform configuration
    if [ ! -f "terraform.tfvars" ] && [ ! -f "main.tf" ]; then
        print_error "No terraform configuration found in current directory"
        return 1
    fi
    
    while [ $attempt -le $max_attempts ] && [ "$destroy_success" = false ]; do
        print_status "Destroy attempt $attempt of $max_attempts..."
        
        # Refresh state before destroy attempt
        print_status "Refreshing Terraform state..."
        if ! terraform refresh -auto-approve 2>/dev/null; then
            print_warning "State refresh failed, attempting to continue..."
        fi
        
        # Attempt destroy with tfvars if available
        local destroy_cmd="terraform destroy -auto-approve"
        if [ -f "terraform.tfvars" ]; then
            destroy_cmd="$destroy_cmd -var-file=terraform.tfvars"
        fi
        
        if eval "$destroy_cmd" 2>&1 | tee /tmp/terraform_destroy.log; then
            # Check if Terraform actually destroyed anything
            if grep -q "Resources: 0 destroyed" /tmp/terraform_destroy.log; then
                print_warning "Terraform reports 0 resources destroyed - state may be out of sync"
                print_status "Checking if resources actually exist in AWS..."
                
                # Force a state refresh and try again
                terraform refresh -auto-approve 2>/dev/null || true
                
                # Try destroy again after refresh
                if eval "$destroy_cmd" 2>&1 | tee /tmp/terraform_destroy_retry.log; then
                    if grep -q "Resources: 0 destroyed" /tmp/terraform_destroy_retry.log; then
                        print_warning "Still 0 resources destroyed after refresh - state may be completely out of sync"
                        destroy_success=false
                    else
                        destroy_success=true
                        print_success "Infrastructure destroyed successfully after state refresh"
                    fi
                else
                    destroy_success=false
                fi
            else
                destroy_success=true
                print_success "Infrastructure destroyed successfully"
            fi
        else
            print_warning "Destroy attempt $attempt failed"
            print_status "Last few lines of destroy output:"
            tail -10 /tmp/terraform_destroy.log 2>/dev/null || echo "No log available"
            
            if [ $attempt -lt $max_attempts ]; then
                print_status "Trying targeted destroy for common problematic resources..."
                
                # Try to destroy resources that commonly cause issues in order
                local problematic_resources=(
                    "aws_lambda_event_source_mapping.event_processing_trigger"
                    "module.lambda.aws_lambda_event_source_mapping.events_stream"
                    "module.api_gateway.aws_lambda_permission.dashboard_api_gateway"
                    "module.api_gateway.aws_lambda_permission.events_api_gateway"
                    "module.api_gateway.aws_lambda_permission.filters_api_gateway"
                    "aws_lambda_permission.eventbridge_cross_region"
                    "module.frontend.null_resource.build_and_upload"
                    "module.frontend.aws_cloudfront_distribution.frontend"
                    "module.api_gateway"
                    "module.lambda"
                    "module.eventbridge_us_east_1_deployment"
                    "module.eventbridge_us_east_1_monitoring"
                    "module.eventbridge_us_east_2"
                    "module.eventbridge_us_west_1"
                    "module.eventbridge_us_west_2"
                    "module.eventbridge_eu_west_1"
                    "module.sqs"
                    "module.dynamodb"
                    "module.frontend"
                    "module.cognito"
                    "module.cloudwatch"
                    "module.iam"
                )
                
                for resource in "${problematic_resources[@]}"; do
                    print_status "Attempting to destroy: $resource"
                    if terraform destroy -target="$resource" -auto-approve 2>&1 | grep -q "No instances found"; then
                        print_status "Resource $resource not found (already destroyed)"
                    elif terraform destroy -target="$resource" -auto-approve; then
                        print_status "Successfully destroyed: $resource"
                    else
                        print_warning "Failed to destroy: $resource"
                    fi
                    sleep 2
                done
                
                # Try a state refresh after targeted destroys
                print_status "Refreshing state after targeted destroys..."
                terraform refresh -auto-approve 2>/dev/null || true
                
                print_status "Waiting 15 seconds before retry..."
                sleep 15
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    if [ "$destroy_success" = false ]; then
        print_error "All destroy attempts failed. Manual cleanup may be required."
        
        # Show what resources are still in state
        print_status "Remaining resources in Terraform state:"
        STATE_RESOURCES=$(terraform state list 2>/dev/null)
        if [ -n "$STATE_RESOURCES" ]; then
            echo "$STATE_RESOURCES"
            echo ""
            print_status "Detailed troubleshooting steps:"
            print_status "1. Check AWS Console for remaining resources"
            print_status "2. Try destroying specific resources: terraform destroy -target=<resource_name>"
            print_status "3. Check for resources in multiple regions (EventBridge rules)"
            print_status "4. Look for dependency issues in the destroy log above"
            print_status "5. Use AWS CLI to delete stubborn resources manually"
            
            # Show the last error from the log
            if [ -f "/tmp/terraform_destroy.log" ]; then
                print_status "Last error details:"
                grep -A 5 -B 5 "Error:" /tmp/terraform_destroy.log | tail -20 || echo "No specific error found"
            fi
        else
            print_warning "Terraform state is empty but AWS resources still exist!"
            print_status "This suggests state corruption or resources created outside Terraform."
            print_status "Offering manual cleanup options..."
            
            # Offer manual cleanup
            print_status "Would you like to attempt manual cleanup of detected resources? (y/N)"
            read -r manual_cleanup
            if [[ "$manual_cleanup" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                manual_resource_cleanup
            fi
        fi
        
        # Still mark as partially successful to continue with cleanup
        print_warning "Continuing with local cleanup despite destroy failures..."
    fi
}

# Function to manually clean up resources when Terraform state is out of sync
manual_resource_cleanup() {
    print_status "Attempting manual cleanup of detected resources..."
    
    # Try to determine the naming pattern from terraform.tfvars
    local name_pattern="health-dashboard"  # Default fallback
    local tfvars_file="terraform.tfvars"
    
    if [ -f "$tfvars_file" ]; then
        # Extract project name
        local project_name=$(grep 'project_name' "$tfvars_file" | cut -d'"' -f2 2>/dev/null || echo "health-dashboard")
        
        # Extract naming convention components
        local prefix=$(awk '/naming_convention = {/,/}/ { if ($1 == "prefix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
        local suffix=$(awk '/naming_convention = {/,/}/ { if ($1 == "suffix") { gsub(/[",]/, "", $3); print $3 } }' "$tfvars_file" 2>/dev/null || echo "")
        
        # Build the expected name pattern
        name_pattern="$project_name"
        if [ -n "$prefix" ]; then
            name_pattern="$prefix-$name_pattern"
        fi
        if [ -n "$suffix" ]; then
            name_pattern="$name_pattern-$suffix"
        fi
    fi
    
    print_status "Using pattern: $name_pattern"
    
    # Clean up Lambda functions
    print_status "Cleaning up Lambda functions..."
    local lambda_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '$name_pattern')].[FunctionName]" --output text 2>/dev/null | grep -v "backend\|terraform" || true)
    for func in $lambda_functions; do
        if [ -n "$func" ]; then
            print_status "Deleting Lambda function: $func"
            aws lambda delete-function --function-name "$func" 2>/dev/null || print_warning "Failed to delete $func"
        fi
    done
    
    # Clean up DynamoDB tables
    print_status "Cleaning up DynamoDB tables..."
    local all_tables=$(aws dynamodb list-tables --query "TableNames" --output text 2>/dev/null || true)
    for table in $all_tables; do
        if [[ "$table" =~ $name_pattern.*(events|filters|counts)$ ]] && [[ ! "$table" =~ backend ]]; then
            print_status "Deleting DynamoDB table: $table"
            aws dynamodb delete-table --table-name "$table" 2>/dev/null || print_warning "Failed to delete $table"
        fi
    done
    
    # Clean up S3 buckets (frontend)
    print_status "Cleaning up S3 buckets..."
    local s3_buckets=$(aws s3 ls | grep "$name_pattern" | grep -v "backend\|terraform" | awk '{print $3}' || true)
    for bucket in $s3_buckets; do
        if [ -n "$bucket" ]; then
            print_status "Emptying and deleting S3 bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            aws s3 rb "s3://$bucket" 2>/dev/null || print_warning "Failed to delete $bucket"
        fi
    done
    
    # Clean up API Gateway
    print_status "Cleaning up API Gateway..."
    local api_ids=$(aws apigateway get-rest-apis --query "items[?contains(name, '$name_pattern')].id" --output text 2>/dev/null || true)
    for api_id in $api_ids; do
        if [ -n "$api_id" ]; then
            print_status "Deleting API Gateway: $api_id"
            aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || print_warning "Failed to delete API $api_id"
        fi
    done
    
    print_status "Manual cleanup completed. Some resources may take time to fully delete."
}

# Function to destroy infrastructure
destroy_infrastructure() {
    print_warning "This will destroy ALL infrastructure. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        # Detect deployment region from existing tfvars
        DEPLOY_REGION="us-east-1"  # default
        if [ -f "environment/terraform.tfvars" ]; then
            DEPLOY_REGION=$(grep 'aws_region' "environment/terraform.tfvars" | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
            ENV_NAME=$(grep '^environment' "environment/terraform.tfvars" | cut -d'"' -f2 2>/dev/null || echo "unknown")
            print_status "Detected deployment region: $DEPLOY_REGION for environment: $ENV_NAME"
        fi
        
        # Try to find backend configuration
        BACKEND_BUCKET=""
        BACKEND_TABLE=""
        
        if [ -f "backend-config.sh" ]; then
            source backend-config.sh
            BACKEND_BUCKET="$TF_BACKEND_BUCKET"
            BACKEND_TABLE="$TF_BACKEND_TABLE"
            print_status "Found backend config: bucket=$BACKEND_BUCKET, table=$BACKEND_TABLE"
        else
            print_status "Backend config not found, attempting auto-detection..."
            # Try to find backend resources by pattern
            BACKEND_BUCKET=$(aws s3 ls | grep "health-dashboard.*terraform-state" | awk '{print $3}' | head -1 2>/dev/null || echo "")
            BACKEND_TABLE=$(aws dynamodb list-tables --query "TableNames[?contains(@, 'health-dashboard') && contains(@, 'terraform-locks')]" --output text 2>/dev/null | head -1 || echo "")
            
            if [ -n "$BACKEND_BUCKET" ] && [ -n "$BACKEND_TABLE" ]; then
                print_status "Auto-detected backend: bucket=$BACKEND_BUCKET, table=$BACKEND_TABLE"
                # Recreate backend config for consistency
                echo "export TF_BACKEND_BUCKET='$BACKEND_BUCKET'" > backend-config.sh
                echo "export TF_BACKEND_TABLE='$BACKEND_TABLE'" >> backend-config.sh
            fi
        fi
        
        
        print_status "Destroying main infrastructure..."
        if [ -n "$BACKEND_BUCKET" ] && [ -n "$BACKEND_TABLE" ]; then
            cd environment
            
            # Initialize with backend configuration using detected region
            print_status "Initializing terraform with backend configuration..."
            if ! terraform init -backend-config="bucket=$BACKEND_BUCKET" \
                              -backend-config="key=environment/terraform.tfstate" \
                              -backend-config="region=$DEPLOY_REGION" >/dev/null 2>&1; then
                print_error "Failed to initialize terraform with backend. Trying local state..."
                terraform init -migrate-state >/dev/null 2>&1 || true
            fi
            
            # Robust destroy with multiple attempts and better error handling
            destroy_with_retry
            
            # Check if destroy was actually successful before removing marker
            if check_resources_destroyed; then
                # Remove the deployment marker file only if resources are actually gone
                if [ -f ".deployment_marker" ]; then
                    rm -f .deployment_marker
                    print_status "Removed deployment marker file"
                fi
            else
                print_warning "Some resources may still exist - keeping deployment marker"
            fi
            
            cd ../..
        else
            print_warning "Backend not found. Attempting local state destroy..."
            cd environment
            if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
                print_status "Found local state, attempting destroy..."
                terraform init >/dev/null 2>&1 || true
                destroy_with_retry
                
                # Clean up deployment marker after local state destroy
                if [ -f ".deployment_marker" ]; then
                    rm -f .deployment_marker
                    print_status "Removed deployment marker file"
                fi
            else
                print_warning "No terraform state found. Infrastructure may already be destroyed."
                # Clean up deployment marker even if no state found
                if [ -f ".deployment_marker" ]; then
                    rm -f .deployment_marker
                    print_status "Removed deployment marker file (no state found)"
                fi
            fi
            cd ../..
        fi
        
        # Go back to backend directory before destroying backend infrastructure
        cd ..
        
        print_warning "Do you also want to destroy the backend storage (S3 + DynamoDB)? (y/N)"
        read -r backend_response
        if [[ "$backend_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            destroy_backend_infrastructure "$BACKEND_BUCKET" "$BACKEND_TABLE" "$DEPLOY_REGION"
        else
            print_success "Main infrastructure destroyed (backend preserved)"
        fi
        
        # Final cleanup - ensure deployment marker is removed after successful destroy
        if [ -f "environment/.deployment_marker" ]; then
            rm -f environment/.deployment_marker
            print_status "Final cleanup: Removed deployment marker file"
        fi
    else
        print_warning "Destruction cancelled"
    fi
}

# Function to destroy backend infrastructure
destroy_backend_infrastructure() {
    local BACKEND_BUCKET="$1"
    local BACKEND_TABLE="$2"
    local DEPLOY_REGION="$3"
    
    print_status "Destroying backend infrastructure..."
    

    
    if [ -n "$BACKEND_BUCKET" ] && [ -n "$BACKEND_TABLE" ]; then
        
        # Try different paths to find backend-setup
        if [ -d "../backend-setup" ]; then
            cd ../backend-setup
        elif [ -d "backend-setup" ]; then
            cd backend-setup
        elif [ -d "../../backend-setup" ]; then
            cd ../../backend-setup
        elif [ -d "cloudops-command-center/backend/backend-setup" ]; then
            cd cloudops-command-center/backend/backend-setup
        else
            print_error "Cannot find backend-setup directory from $(pwd)"
            print_status "Available directories:"
            ls -la ../ 2>/dev/null || ls -la ./ 2>/dev/null || echo "Cannot list directories"
            exit 1
        fi
        
        print_status "Changed to backend-setup directory: $(pwd)"
        
        # If no state file exists, recreate it by importing existing resources
        if [ ! -f "terraform.tfstate" ]; then
            print_status "Recreating backend state for safe destruction..."
            terraform init >/dev/null 2>&1 || true
            
            # Import existing resources into terraform state
            terraform import -var="aws_profile=$SELECTED_AWS_PROFILE" -var="aws_region=$DEPLOY_REGION" aws_s3_bucket.terraform_state "$BACKEND_BUCKET" 2>/dev/null || true
            terraform import -var="aws_profile=$SELECTED_AWS_PROFILE" -var="aws_region=$DEPLOY_REGION" aws_dynamodb_table.terraform_locks "$BACKEND_TABLE" 2>/dev/null || true
            terraform import -var="aws_profile=$SELECTED_AWS_PROFILE" -var="aws_region=$DEPLOY_REGION" random_id.bucket_suffix "$(echo $BACKEND_BUCKET | grep -o '[^-]*$')" 2>/dev/null || true
        fi
        
        # Now destroy with proper state
        if ! terraform destroy -auto-approve -var="aws_profile=$SELECTED_AWS_PROFILE" -var="aws_region=$DEPLOY_REGION"; then
            print_warning "Backend destruction failed, attempting manual cleanup..."
            manual_backend_cleanup "$BACKEND_BUCKET" "$BACKEND_TABLE"
        fi
        cd ..
        
        # Clean local files when backend is destroyed
        cleanup_local_files
        
        print_success "All infrastructure and backend destroyed"
    else
        print_warning "Backend resources not found or already clean"
    fi
}

# Function to empty S3 buckets before destroy
empty_s3_buckets() {
    local backend_bucket="$1"
    
    print_status "Emptying S3 buckets before destroy..."
    
    # Empty backend bucket if provided
    if [ -n "$backend_bucket" ]; then
        print_status "Emptying backend S3 bucket: $backend_bucket"
        aws s3 rm s3://$backend_bucket --recursive 2>/dev/null || true
    fi
    
    # Find and empty frontend bucket
    local frontend_bucket=$(aws s3 ls | grep "health-dashboard.*frontend" | awk '{print $3}' | head -1 2>/dev/null || echo "")
    if [ -n "$frontend_bucket" ]; then
        print_status "Emptying frontend S3 bucket: $frontend_bucket"
        aws s3 rm s3://$frontend_bucket --recursive 2>/dev/null || true
    fi
    
    print_success "S3 buckets emptied"
}

# Function for manual backend cleanup
manual_backend_cleanup() {
    local BACKEND_BUCKET="$1"
    local BACKEND_TABLE="$2"
    
    # Try to delete S3 bucket manually
    if [ -n "$BACKEND_BUCKET" ]; then
        print_status "Attempting to empty and delete S3 bucket: $BACKEND_BUCKET"
        aws s3 rm s3://$BACKEND_BUCKET --recursive 2>/dev/null || true
        aws s3 rb s3://$BACKEND_BUCKET --force 2>/dev/null || true
    fi
    
    # Try to delete DynamoDB table manually
    if [ -n "$BACKEND_TABLE" ]; then
        print_status "Attempting to delete DynamoDB table: $BACKEND_TABLE"
        aws dynamodb delete-table --table-name "$BACKEND_TABLE" 2>/dev/null || true
    fi
    
    print_warning "Manual cleanup attempted - some resources may still exist"
}

# Function to cleanup local files
cleanup_local_files() {
    print_status "Cleaning local configuration files..."
    rm -rf environment/.terraform* 2>/dev/null || true
    rm -rf backend-setup/.terraform* 2>/dev/null || true
    rm -f environment/terraform.tfvars 2>/dev/null || true
    rm -f environment/tfplan 2>/dev/null || true
    rm -f backend-setup/terraform.tfstate* 2>/dev/null || true
    rm -f environment/terraform.tfstate* 2>/dev/null || true
    rm -f backend-config.sh 2>/dev/null || true
    
    # Clean environment variables
    clean_env_vars
}



# Parse arguments
REDEPLOY_MODE="false"
SKIP_BEDROCK_VALIDATION="false"
COMMAND="deploy"  # Default command

for arg in "$@"; do
    case $arg in
        --redeploy|--no-prompts)
            REDEPLOY_MODE="true"
            shift
            ;;
        --skip-bedrock-validation)
            SKIP_BEDROCK_VALIDATION="true"
            shift
            ;;
        --destroy)
            COMMAND="destroy"
            shift
            ;;
        --configure)
            COMMAND="configure"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

# Function to configure Bedrock model selection
configure_bedrock_model() {
    print_status ""
    print_status "=== Bedrock Model Selection ==="
    print_status "Select the Claude model to use for AWS Health event analysis."
    print_status "Models are automatically configured for deployment region: $DEPLOYMENT_REGION"
    print_status "Using '$BEDROCK_REGION_PREFIX.anthropic.*' model prefix"
    print_status ""
    
    # Define available models based on deployment region
    if [ "$DEPLOYMENT_REGION" = "us-east-1" ]; then
        MODELS=("us.anthropic.claude-sonnet-4-20250514-v1:0" "us.anthropic.claude-3-7-sonnet-20250219-v1:0")
        REGION_PREFIX="us"
    elif [ "$DEPLOYMENT_REGION" = "ap-southeast-1" ]; then
        MODELS=("apac.anthropic.claude-sonnet-4-20250514-v1:0" "apac.anthropic.claude-3-7-sonnet-20250219-v1:0")
        REGION_PREFIX="apac"
    else
        # This should not happen with the limited region selection, but keeping as fallback
        MODELS=("us.anthropic.claude-sonnet-4-20250514-v1:0" "us.anthropic.claude-3-7-sonnet-20250219-v1:0")
        REGION_PREFIX="us"
        print_warning "Unknown deployment region, defaulting to US models"
    fi
    
    MODEL_NAMES=("Claude Sonnet 4 (Latest)" "Claude 3.7 Sonnet")
    MODEL_DESCRIPTIONS=("Most advanced model with best analysis quality" "Balanced performance and cost")
    
    print_status "Available models for region $DEPLOYMENT_REGION ($REGION_PREFIX prefix):"
    for i in "${!MODELS[@]}"; do
        model="${MODELS[i]}"
        name="${MODEL_NAMES[i]}"
        description="${MODEL_DESCRIPTIONS[i]}"
        echo "  $((i+1))) $name"
        echo "      Model ID: $model"
        echo "      Description: $description"
        echo ""
    done
    
    while true; do
        read -p "Select Bedrock model (1-${#MODELS[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MODELS[@]}" ]; then
            SELECTED_MODEL="${MODELS[$((choice-1))]}"
            SELECTED_MODEL_NAME="${MODEL_NAMES[$((choice-1))]}"
            print_success "Selected: $SELECTED_MODEL_NAME"
            print_status "Model ID: $SELECTED_MODEL"
            
            # Validate Bedrock model access immediately after selection
            if [ "$SKIP_BEDROCK_VALIDATION" = "false" ]; then
                if ! validate_bedrock_access "$DEPLOYMENT_REGION" "$SELECTED_MODEL"; then
                    print_error "Cannot proceed with deployment due to Bedrock access issues"
                    print_status "Please enable model access and try again"
                    print_status "Or use --skip-bedrock-validation flag to bypass this check"
                    exit 1
                fi
            else
                print_warning "Skipping Bedrock model validation (--skip-bedrock-validation flag used)"
            fi
            
            break
        else
            print_warning "Invalid choice. Please enter a number between 1 and ${#MODELS[@]}."
        fi
    done
    
    # Append to terraform.tfvars
    cat >> "$TFVARS_FILE" << EOF

# Bedrock Model Configuration
bedrock_model_id = "$SELECTED_MODEL"
EOF
    
    print_success "Bedrock model configuration saved"
}

# Function to configure DynamoDB TTL
configure_dynamodb_ttl() {
    print_status ""
    print_status "=== DynamoDB Events Table TTL Configuration ==="
    print_status "Configure how long AWS Health events are retained in the database."
    print_status "After this period, events will be automatically deleted to manage storage costs."
    print_status ""
    
    # Define available TTL options
    TTL_OPTIONS=(60 90 180)
    TTL_DESCRIPTIONS=("60 days (2 months)" "90 days (3 months)" "180 days (6 months)")
    
    print_status "Available retention periods:"
    for i in "${!TTL_OPTIONS[@]}"; do
        days="${TTL_OPTIONS[i]}"
        description="${TTL_DESCRIPTIONS[i]}"
        echo "  $((i+1))) $description"
    done
    
    echo ""
    while true; do
        read -p "Select TTL retention period (1-${#TTL_OPTIONS[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TTL_OPTIONS[@]}" ]; then
            SELECTED_TTL_DAYS="${TTL_OPTIONS[$((choice-1))]}"
            SELECTED_TTL_DESCRIPTION="${TTL_DESCRIPTIONS[$((choice-1))]}"
            print_success "Selected: $SELECTED_TTL_DESCRIPTION"
            break
        else
            print_warning "Invalid choice. Please enter a number between 1 and ${#TTL_OPTIONS[@]}."
        fi
    done
    
    # Append to terraform.tfvars
    cat >> "$TFVARS_FILE" << EOF

# DynamoDB TTL Configuration
events_table_ttl_days = $SELECTED_TTL_DAYS
EOF
    
    print_success "DynamoDB TTL configuration saved"
}

# Function to configure email notifications
configure_email_notifications() {
    print_status ""
    print_status "=== Email Notification Configuration ==="
    print_status "Configure scheduled email summaries of open AWS Health events."
    print_status "Emails will be sent weekly with a summary and Excel attachment."
    print_status ""
    
    # Ask if user wants to enable email notifications
    while true; do
        read -p "Enable email notifications? (y/N): " enable_choice
        case $enable_choice in
            [Yy]* )
                ENABLE_EMAIL_NOTIFICATIONS="true"
                print_success "Email notifications will be enabled"
                break
                ;;
            [Nn]* | "" )
                ENABLE_EMAIL_NOTIFICATIONS="false"
                print_status "Email notifications will be disabled"
                
                # Append disabled configuration to terraform.tfvars
                cat >> "$TFVARS_FILE" << EOF

# Email Notification Configuration (optional)
enable_email_notifications = false                # Set to true to enable email notifications
# sender_email = "your-verified-email@example.com"  # Must be verified in SES (required if enabled)
# master_recipient_email = "admin@example.com"      # Receives all health event summaries (required if enabled)
# email_schedule_expression = "cron(0 1 ? * MON *)" # Monday 9 AM UTC+8 = Monday 1 AM UTC
EOF
                print_success "Email notification configuration saved (disabled)"
                return
                ;;
            * )
                print_warning "Please answer yes (y) or no (n)"
                ;;
        esac
    done
    
    # If enabled, collect required configuration
    print_status ""
    print_status "Email notifications require:"
    print_status "1. A verified sender email address in Amazon SES"
    print_status "2. A master recipient email address"
    print_status "3. A schedule for sending reports (default: Monday 9 AM UTC+8)"
    print_status ""
    
    # Get sender email
    while true; do
        read -p "Enter sender email address (must be verified in SES): " sender_email
        if [[ "$sender_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_success "Sender email: $sender_email"
            break
        else
            print_warning "Invalid email format. Please try again."
        fi
    done
    
    # Get master recipient email
    while true; do
        read -p "Enter master recipient email address: " master_recipient_email
        if [[ "$master_recipient_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_success "Master recipient email: $master_recipient_email"
            break
        else
            print_warning "Invalid email format. Please try again."
        fi
    done
    
    # Configure schedule
    print_status ""
    print_status "Email Schedule Options:"
    echo "  1) Weekly - Monday 9 AM UTC+8 (Monday 1 AM UTC)"
    echo "  2) Weekly - Friday 9 AM UTC+8 (Friday 1 AM UTC)"
    echo "  3) Daily - 9 AM UTC+8 (1 AM UTC)"
    echo "  4) Custom cron expression"
    echo ""
    
    while true; do
        read -p "Select schedule option (1-4): " schedule_choice
        case $schedule_choice in
            1)
                EMAIL_SCHEDULE="cron(0 1 ? * MON *)"
                print_success "Selected: Weekly - Monday 9 AM UTC+8"
                break
                ;;
            2)
                EMAIL_SCHEDULE="cron(0 1 ? * FRI *)"
                print_success "Selected: Weekly - Friday 9 AM UTC+8"
                break
                ;;
            3)
                EMAIL_SCHEDULE="cron(0 1 * * ? *)"
                print_success "Selected: Daily - 9 AM UTC+8"
                break
                ;;
            4)
                read -p "Enter custom cron expression: " custom_cron
                EMAIL_SCHEDULE="$custom_cron"
                print_success "Selected: Custom - $custom_cron"
                break
                ;;
            *)
                print_warning "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
    
    # Append to terraform.tfvars
    cat >> "$TFVARS_FILE" << EOF

# Email Notification Configuration
enable_email_notifications = true
sender_email = "$sender_email"
master_recipient_email = "$master_recipient_email"
email_schedule_expression = "$EMAIL_SCHEDULE"
EOF
    
    print_success "Email notification configuration saved"
    print_status ""
    print_warning "⚠️  IMPORTANT: Email Verification Required"
    print_status ""
    print_status "Before deployment, you must verify email addresses in Amazon SES:"
    print_status "  • Sender email: $sender_email"
    print_status "  • Recipient email: $master_recipient_email (required if SES is in sandbox mode)"
    print_status ""
    print_status "To verify emails, use one of these methods:"
    print_status ""
    print_status "Option 1 - AWS CLI:"
    print_status "  aws ses verify-email-identity --email-address $sender_email"
    print_status "  aws ses verify-email-identity --email-address $master_recipient_email"
    print_status ""
    print_status "Option 2 - AWS Console:"
    print_status "  Go to: AWS Console → Amazon SES → Verified identities → Create identity"
    print_status ""
    print_status "Option 3 - Check verification status:"
    print_status "  aws ses get-identity-verification-attributes --identities $sender_email $master_recipient_email"
    print_status ""
}

# Main script logic
case "$COMMAND" in
    "deploy")
        if [ "$REDEPLOY_MODE" = "true" ]; then
            print_status "Starting AWS Health Dashboard redeployment (no prompts)..."
        else
            print_status "Starting AWS Health Dashboard deployment..."
        fi
        clean_env_vars
        check_prerequisites
        configure_deployment
        
        # Ensure AWS profile is set BEFORE any AWS operations (including Bedrock validation)
        if [ -z "$AWS_PROFILE" ] && [ -f "environment/terraform.tfvars" ]; then
            SELECTED_AWS_PROFILE=$(grep 'aws_profile' "environment/terraform.tfvars" | cut -d'"' -f2)
            if [ -n "$SELECTED_AWS_PROFILE" ]; then
                export AWS_PROFILE="$SELECTED_AWS_PROFILE"
                print_status "Set AWS profile for operations: $SELECTED_AWS_PROFILE"
            fi
        fi
        
        # Check Bedrock access for existing configurations in redeploy mode (after profile is set)
        if [ "$SKIP_BEDROCK_VALIDATION" = "false" ] && ([ "$REDEPLOY_MODE" = "true" ] || [ "$USING_EXISTING_CONFIG" = "true" ]); then
            check_existing_bedrock_access
        elif [ "$SKIP_BEDROCK_VALIDATION" = "true" ]; then
            print_warning "Skipping Bedrock validation for existing configuration (--skip-bedrock-validation flag used)"
        fi
        
        setup_backend
        deploy_infrastructure
        print_success "Deployment complete!"
        ;;
    "destroy")
        print_status "Starting AWS Health Dashboard destruction..."
        setup_aws_profile
        destroy_infrastructure
        ;;
    "configure")
        print_status "Starting AWS Health Dashboard configuration..."
        configure_deployment
        print_success "Configuration complete!"
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac