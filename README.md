# AWS Health Dashboard

An intelligent AWS Health event monitoring and analysis system that automatically captures, analyzes, and categorizes AWS Health events across multiple regions using AI-powered insights.

## What is this project?

This project provides a complete infrastructure solution for monitoring AWS Health events across your organization. It automatically:
- **Captures** AWS Health events from multiple regions in real-time
- **Analyzes** events using Amazon Bedrock AI for risk assessment and impact analysis
- **Categorizes** events by criticality, time sensitivity, and business impact
- **Stores** processed events with intelligent data retention
- **Notifies** account owners via personalized email summaries with Excel reports
- **Provides** a React-based dashboard for visualization and management

## Prerequisites

### AWS Requirements
- **AWS Business/Enterprise Support Plan** (required for Health API access)
- **Organization Health Dashboard** enabled with [delegated administrator account](https://docs.aws.amazon.com/health/latest/ug/register-a-delegated-administrator.html)
- **Bedrock Model Access** enabled for Claude Sonnet models in the delegated administrator account
- **AWS CLI** configured with appropriate credentials

### Local Tools
- **Terraform** >= 1.0
- **AWS CLI** configured with valid credentials
- **Python 3** with pip3 (for Lambda layer building)
- **Node.js & npm** (optional - only if enabling automatic frontend build)

## Architecture

### High-Level Flow
```
AWS Health Events → Multi-Region EventBridge → Central SQS → AI Analysis → Dashboard
```

### Detailed Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   CloudFront    │────│   React App     │────│   API Gateway    │────│   Lambda APIs   │
│     (CDN)       │    │   (S3/Cognito)  │    │   (Authorized)   │    │ (CRUD/Dashboard)│
└─────────────────┘    └─────────────────┘    └─────────┬────────┘    └─────────────────┘
                                                        │
┌─────────────────┐    ┌──────────────────┐    ┌────────┴────────┐
│  EventBridge    │────│   SQS Queue      │────│ Event Processor │
│ (Multi-Region)  │    │ (Parallel Proc.) │    │     Lambda      │
└─────────────────┘    └──────────────────┘    └────────┬────────┘
                                                        │
                       ┌──────────────────┐    ┌────────┴────────┐
                       │    Bedrock AI    │────│    DynamoDB     │
                       │ (Risk Analysis)  │    │ (Events/Counts) │
                       └──────────────────┘    └────────┬────────┘
                                                        │
                                               ┌────────┴────────┐    ┌─────────────────┐
                                               │ Email Processor │────│  Organizations  │
                                               │     Lambda      │    │   (Accounts)    │
                                               └─────────┬───────┘    └─────────────────┘
                                                         │
                                               ┌─────────┴───────┐    ┌─────────────────┐
                                               │  Account Email  │────│ Account Email   │
                                               │   SQS Queue     │    │ Sender Lambda   │
                                               └─────────────────┘    └────────┬────────┘
                                                                               │
                                                                      ┌────────┴─────────┐
                                                                      │  SES + S3        │
                                                                      │ (Email Reports)  │
                                                                      └──────────────────┘
```

**Key Components:**
- **CloudFront CDN**: Global content delivery network for fast React app loading
- **React Dashboard**: S3-hosted SPA with Cognito authentication for event visualization
- **Multi-Region EventBridge**: Captures health events from selected AWS regions
- **SQS Queue**: Buffers events for parallel processing with dead letter queue
- **AI Analysis**: Amazon Bedrock analyzes events for risk, impact, and required actions
- **DynamoDB**: Stores processed events with TTL and live count tracking
- **Email Notifications**: Automated email summaries with Excel reports

## Deployment Options

### First-Time Setup

```bash
cd backend
./deploy.sh
```

**The deployment script will prompt you to configure:**

1. **AWS Profile Selection** - Choose from available AWS CLI profiles
2. **Environment Name** - e.g., 'dev', 'staging', 'prod'
3. **Resource Naming**:
   - Resource prefix (optional)
   - Environment suffix (uses environment name)
   - Random suffix for uniqueness (optional)
4. **Deployment Region** - Choose where this solution will be deployed (recommended: us-east-1)
5. **Health Monitoring Regions** - Select which regions to monitor for health events
6. **Frontend Build** - Enable/disable automatic React app build and deployment
7. **Bedrock Model** - Choose Claude model (ensure model access is enabled first)
8. **Data Retention** - Health events retention duration in DynamoDB (60, 90, or 180 days)
9. **Email Notifications** - Configure automated email summaries:
   - Master email recipient (receives all events)
   - Enable/disable per-account emails
   - Optional CC address for account emails
   - SES sender email address

### Subsequent Changes

**For infrastructure changes:**
```bash
cd backend
./deploy.sh --redeploy  # Uses existing configuration, no prompts
```

**For configuration changes:**
```bash
cd backend
./deploy.sh configure   # Reconfigure settings only
./deploy.sh             # Deploy with new configuration
```

**For backend-only changes (skip frontend build):**

**Temporarily disable frontend build in backend/environment/terraform.tfvars**
```bash
# to redeploy
build_and_upload = true 

# don't redeploy
build_and_upload = false 
```

```bash
# Then redeploy
cd backend
./deploy.sh --redeploy
```

### Testing React App Locally

**After successful deployment:**
```bash
cd frontend/app
npm install
npm run dev
```

**The React app will:**
- Use the deployed API Gateway endpoint
- Connect to the deployed Cognito User Pool
- Access real AWS Health events data
- Run locally at `http://localhost:3000`

### Cleanup

**Destroy main infrastructure (preserves backend storage):**
```bash
cd backend
./deploy.sh destroy
```

**Complete cleanup (including Terraform state storage):**
- Run destroy command above
- When prompted, choose 'y' to also destroy backend storage
- This removes all traces of the deployment

## Email Notifications

The system automatically sends email summaries of AWS Health events with Excel reports attached.

### Email Types

**Master Email** (sent to administrators):
- Contains all open health events across all accounts
- Subject: `AWS Health Events Summary [MASTER] - YYYY-MM-DD`
- Includes summary statistics and account count
- Excel attachment with 3 sheets: Summary, Health Events, Account Email Mapping

**Per-Account Emails** (sent to account owners):
- Contains only events for specific account(s)
- Subject: `AWS Health Events Summary [username] - YYYY-MM-DD`
- Personalized statistics for the account owner
- Excel attachment with 3 sheets: Summary, Health Events, Account Email Mapping

### Email Features

**Smart Attachments**:
- Files < 5 MB: Attached directly to email + S3 download link
- Files ≥ 5 MB: S3 download link only (with size notice)
- Presigned URLs valid for 7 days

**Custom Email Routing**:
- Default: Uses AWS Organizations account owner email
- Override: Configure custom email mappings in DynamoDB
- Consolidation: Multiple accounts can route to one email address

**Email Consolidation**:
When multiple accounts map to the same email address, the system automatically:
- Combines events from all accounts into a single email
- Lists all account IDs in the email body
- Includes events from all accounts in the Excel report

**Optional CC**:
- Configure a CC email address for all account-specific emails
- Useful for central teams to monitor all notifications
- Master email is not affected by CC configuration

### Configuring Custom Email Mappings

To override the default AWS Organizations email routing:

1. **Add records to the account-email-mappings DynamoDB table:**
```json
{
  "accountId": "123456789012",
  "email": "custom@example.com",
  "createdAt": "2025-04-20T16:20:00Z",
  "updatedAt": "2025-04-20T16:20:00Z",
  "notes": "Team email for production accounts"
}
```

2. **Consolidate multiple accounts to one email:**
```json
{
  "accountId": "123456789012",
  "email": "team@example.com"
}
{
  "accountId": "234567890123",
  "email": "team@example.com"
}
```

3. **The system will automatically:**
- Use custom mappings when available
- Fall back to AWS Organizations email if no mapping exists
- Consolidate events when multiple accounts share an email
- Include mapping information in the Excel reports

### Email Schedule

Emails are sent daily at 8:00 AM UTC via EventBridge schedule. Only accounts with open health events receive emails.

## Event Processor Lambda Modes

The Event Processor Lambda function operates in multiple modes depending on how it's triggered. Understanding these modes helps with troubleshooting and manual operations.

### 1. SQS Event Processing (Real-Time)

**Trigger:** EventBridge → SQS Queue → Lambda

**Purpose:** Process individual health events as they occur in real-time

**Event Format:**
```json
{
  "Records": [{
    "eventSource": "aws:sqs",
    "body": "{...health event data...}"
  }]
}
```

**Behavior:**
- Processes events one at a time from SQS queue
- Analyzes with Bedrock if event is new or has incomplete analysis
- Updates DynamoDB with event details and analysis
- Updates live counts table
- Handles EventBridge event format conversion

**When it runs:** Automatically when AWS Health events occur

### 2. DynamoDB Stream Processing (TTL Cleanup)

**Trigger:** DynamoDB TTL deletion → DynamoDB Stream → Lambda

**Purpose:** Decrement counts when events expire via TTL

**Event Format:**
```json
{
  "Records": [{
    "eventSource": "aws:dynamodb",
    "eventName": "REMOVE",
    "userIdentity": {"type": "Service", "principalId": "dynamodb.amazonaws.com"}
  }]
}
```

**Behavior:**
- Detects TTL-deleted events
- Decrements live counts for affected accounts
- Only processes events that were contributing to counts (open/upcoming/scheduled status)

**When it runs:** Automatically when DynamoDB TTL expires events

### 3. Scheduled Sync Mode (Daily)

**Trigger:** EventBridge Scheduled Rule → Lambda

**Purpose:** Catch status changes that didn't trigger EventBridge notifications

**Event Format:**
```json
{
  "mode": "scheduled_sync",
  "lookback_days": 7
}
```

**Behavior:**
- Fetches all events from AWS Health API for last 7 days (configurable)
- Compares with DynamoDB to detect status changes
- Updates events that changed status (e.g., upcoming → closed)
- Skips Bedrock analysis for events with valid existing analysis
- Re-analyzes events with failed or incomplete analysis

**When it runs:** Daily at 2 AM Singapore time (6 PM UTC)

**Why needed:** AWS Health doesn't send EventBridge notifications for all status changes (e.g., routine event closures)

### 4. Batch Processing Mode (Manual)

**Trigger:** Manual Lambda invocation or initial deployment

**Purpose:** Bulk process events for a time range

**Event Format:**
```json
{
  "start_time": "2025-01-01T00:00:00Z",
  "end_time": "2025-01-31T23:59:59Z"
}
```

**Behavior:**
- Fetches all events from AWS Health API for specified time range
- Processes events in bulk
- Analyzes with Bedrock (respects existing valid analysis)
- Useful for initial data population or backfilling

**When it runs:** Manually invoked or during initial deployment

### 5. Single Event Mode (Manual)

**Trigger:** Manual Lambda invocation with specific event ARN

**Purpose:** Process or re-analyze a specific event

**Event Format:**
```json
{
  "event_arn": "arn:aws:health:us-east-1::event/EC2/AWS_EC2_INSTANCE_RETIREMENT/..."
}
```

**Behavior:**
- Fetches details for specific event ARN
- Forces Bedrock analysis (even if event exists)
- Useful for troubleshooting or re-analyzing specific events

**When it runs:** Manually invoked for debugging/testing

### Manual Invocation Examples

**Trigger scheduled sync manually:**
```bash
aws lambda invoke \
  --function-name health-dashboard-dev-<random>-event-processor \
  --payload '{"mode":"scheduled_sync","lookback_days":7}' \
  response.json
```

**Re-analyze specific event:**
```bash
aws lambda invoke \
  --function-name health-dashboard-dev-<random>-event-processor \
  --payload '{"event_arn":"arn:aws:health:..."}' \
  response.json
```

**Batch process date range:**
```bash
aws lambda invoke \
  --function-name health-dashboard-dev-<random>-event-processor \
  --payload '{"start_time":"2025-01-01T00:00:00Z","end_time":"2025-01-31T23:59:59Z"}' \
  response.json
```

## Why Use Remote State?

✅ **Team Collaboration** - Multiple developers can work safely
✅ **State Locking** - Prevents concurrent modifications
✅ **Backup & Versioning** - S3 versioning protects against corruption
✅ **Security** - Encrypted storage
✅ **Audit Trail** - Track who made changes when

## State Storage Options:

| Option | Pros | Cons | Best For |
|--------|------|------|----------|
| **Local** | Simple, fast | No collaboration, no backup | Solo development |
| **S3 + DynamoDB** | Secure, collaborative, locked | Setup required | Teams, production |
| **Terraform Cloud** | Managed, UI, policies | Cost, vendor lock-in | Enterprise |

**Recommendation: Use S3 + DynamoDB for this project.**