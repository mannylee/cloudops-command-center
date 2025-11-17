# AWS Health Events to CSV Script (Python)

This Python script replicates the functionality of the Lambda event processor (`backend/modules/lambda/code/events/index.py`) but outputs health events to a CSV file instead of storing them in DynamoDB.

## Features

- Fetches AWS Health events using the Organization Health Dashboard
- Processes events for multiple accounts in your organization
- Generates simplified descriptions and risk categorizations
- Outputs data in the same CSV format as the DynamoDB table structure
- Supports filtering by event categories and time windows

## Prerequisites

1. **Python 3.7+** - Required for running the script
2. **boto3** - AWS SDK for Python (install via `pip install boto3`)
3. **AWS credentials** - Must be configured via AWS CLI, environment variables, or IAM roles
4. **AWS Organization Health Dashboard** - Must be enabled in your AWS organization
5. **Appropriate IAM permissions** for:
   - `health:DescribeEventsForOrganization`
   - `health:DescribeAffectedAccountsForOrganization`
   - `health:DescribeAffectedEntitiesForOrganization`
   - `organizations:ListAccounts`
   - `bedrock:InvokeModel` (if using Bedrock analysis)
   - `bedrock:ListFoundationModels` (if using Bedrock analysis)

**Important**: All AWS Health API calls are made to the `us-east-1` region, as this is where the AWS Health service is centralized.

## Installation

```bash
# Install Python dependencies
pip install boto3

# Configure AWS credentials (choose one method)
aws configure  # Interactive configuration
# OR set environment variables
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

## Usage

### Basic Usage

```bash
python aws-health-events-to-csv.py
```

### Command Line Arguments

```bash
# Show help
python aws-health-events-to-csv.py --help

# Custom analysis window and categories
python aws-health-events-to-csv.py --days 14 --categories "issue,scheduledChange"

# Enable Bedrock AI analysis
python aws-health-events-to-csv.py --bedrock

# Custom output directory and file
python aws-health-events-to-csv.py --output-dir ./reports --output-file my-events.csv

# Full customization with Bedrock
python aws-health-events-to-csv.py \
  --days 30 \
  --categories "issue,accountNotification" \
  --output-dir ./reports \
  --bedrock \
  --model "anthropic.claude-3-haiku-20240307-v1:0" \
  --temperature 0.2
```

### Available Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--days` | `-d` | Analysis window in days | 90 |
| `--categories` | `-c` | Event categories (comma-separated) | "all" |
| `--output-dir` | `-o` | Output directory | "./output" |
| `--output-file` | `-f` | Output filename | "health-events-YYYY-MM-DD_HH-MM.csv" |
| `--bedrock` | `-b` | Enable Bedrock AI analysis | false |
| `--model` | `-m` | Bedrock model ID | "anthropic.claude-3-sonnet-20240229-v1:0" |
| `--temperature` | `-t` | Bedrock temperature (0.0-1.0) | 0.1 |
| `--top-p` | `-p` | Bedrock top-p (0.0-1.0) | 0.9 |
| `--max-tokens` | `-x` | Bedrock max tokens | 4000 |
| `--help` | `-h` | Show help message | - |

## Bedrock AI Analysis

When enabled with the `--bedrock` flag, the script uses Amazon Bedrock to provide enhanced analysis of health events, including:

- **Intelligent Risk Assessment**: AI-powered evaluation of event criticality and impact
- **Detailed Impact Analysis**: Specific analysis of potential outages and connectivity issues
- **Actionable Recommendations**: Tailored required actions based on event context
- **Consequence Prediction**: Clear explanation of what happens if events are ignored

### Supported Bedrock Models

- `anthropic.claude-3-sonnet-20240229-v1:0` (default) - Balanced performance and cost
- `anthropic.claude-3-haiku-20240307-v1:0` - Faster and more cost-effective
- `anthropic.claude-3-opus-20240229-v1:0` - Most capable but expensive

### Bedrock Requirements

1. **Bedrock Access**: Your AWS account must have access to Amazon Bedrock
2. **Model Access**: The chosen model must be enabled in your Bedrock console
3. **IAM Permissions**: Your credentials need `bedrock:InvokeModel` permission
4. **Region**: Bedrock requests are made to `us-east-1` region

## Output

The script creates a CSV file named `health-events-YYYY-MM-DD_HH-MM.csv` in the output directory with the following columns:

- `eventArn` - Unique identifier for the health event
- `accountId` - AWS account ID affected by the event
- `accountName` - Human-readable account name
- `affectedResources` - List of affected AWS resources
- `analysisTimestamp` - When the analysis was performed
- `analysisVersion` - Version of the analysis logic
- `Category` - Event category (currently empty, reserved for future use)
- `consequencesIfIgnored` - What happens if no action is taken
- `critical` - Boolean indicating if the event is critical
- `description` - Full event description from AWS Health
- `eventImpactType` - Type of impact (Security, Maintenance, etc.)
- `eventType` - AWS Health event type code
- `eventTypeCategory` - Category (issue, scheduledChange, accountNotification)
- `impactAnalysis` - Analysis of the event's impact
- `lastUpdateTime` - When the event was last updated
- `region` - AWS region where the event occurred
- `requiredActions` - Recommended actions to take
- `riskCategory` - Risk category (Security, Availability, etc.)
- `riskLevel` - Risk level (LOW, MEDIUM, HIGH)
- `service` - AWS service affected
- `simplifiedDescription` - Human-readable event summary
- `startTime` - When the event started
- `statusCode` - Event status (open, closed, upcoming)
- `timeSensitivity` - How urgent the event is (Routine, Urgent, Immediate)
- `ttl` - TTL timestamp for data retention (6 months from last update)

## Differences from Lambda Function

This Python script closely replicates the Lambda function's capabilities with these differences:

1. **Optional Bedrock Integration** - Can use the same AI analysis as the Lambda function when `--bedrock` is enabled
2. **CSV Output** - Outputs to CSV instead of storing in DynamoDB
3. **No SQS Processing** - Processes events synchronously instead of using SQS for parallel processing
4. **Command Line Interface** - Uses command-line arguments instead of environment variables
5. **Simplified Retry Logic** - Basic retry for Bedrock calls instead of advanced concurrent processing optimization
6. **Python Implementation** - Uses boto3 SDK instead of AWS CLI commands for better error handling and type safety

## Troubleshooting

### Common Issues

1. **"Organization Health Dashboard not enabled"**
   - Enable the Organization Health Dashboard in your AWS organization
   - Ensure you have the necessary permissions
   - Note: Health API calls are made to `us-east-1` region regardless of your default region

2. **"AWS credentials not configured"**
   - Configure AWS credentials using `aws configure`
   - Or use environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
   - Or use IAM roles if running on EC2/Lambda

3. **"boto3 not found"**
   - Install boto3: `pip install boto3`

4. **"Bedrock access not available"**
   - Ensure Amazon Bedrock is enabled in your AWS account
   - Verify you have `bedrock:InvokeModel` and `bedrock:ListFoundationModels` permissions
   - Check that the specified model is available in the `us-east-1` region

5. **Empty CSV file**
   - Check if there are any health events in the specified time window
   - Verify your event category filters
   - Ensure your account has access to organization-wide health events

6. **Bedrock analysis failures**
   - The script will automatically fall back to rule-based analysis if Bedrock fails
   - Check CloudTrail logs for specific Bedrock error details
   - Verify your model ID is correct and the model is enabled

### Debug Mode

For verbose output, you can modify the logging level in the script or add print statements to debug specific issues.

## Example Output

The CSV output will look similar to the test file `backend/test/chanshih-health-events-2025-07-30.csv`, containing health events with their analysis and categorization.

### Sample Commands

```bash
# Quick analysis of last 90 days with basic categorization
python aws-health-events-to-csv.py

# Comprehensive analysis with AI for last 30 days
python aws-health-events-to-csv.py --days 30 --bedrock

# Focus on critical issues only with fast AI model
python aws-health-events-to-csv.py \
  --categories "issue" \
  --bedrock \
  --model "anthropic.claude-3-haiku-20240307-v1:0"

# Generate monthly report with detailed analysis
python aws-health-events-to-csv.py \
  --days 30 \
  --output-dir ./monthly-reports \
  --output-file "health-events-$(date +%Y-%m).csv" \
  --bedrock \
  --temperature 0.05
```

## Integration

This Python script can be integrated into CI/CD pipelines, scheduled cron jobs, or monitoring systems to regularly export AWS Health events for analysis and reporting. The script can be containerized using Docker or deployed as a scheduled Lambda function for automated execution.