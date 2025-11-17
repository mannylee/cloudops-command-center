# AWS Health Dashboard

An intelligent AWS Health event monitoring and analysis system that automatically captures, analyzes, and categorizes AWS Health events across multiple regions using AI-powered insights.

## What is this project?

This project provides a complete infrastructure solution for monitoring AWS Health events across your organization. It automatically:
- **Captures** AWS Health events from multiple regions in real-time
- **Analyzes** events using Amazon Bedrock AI for risk assessment and impact analysis
- **Categorizes** events by criticality, time sensitivity, and business impact
- **Stores** processed events with intelligent data retention
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
└─────────────────┘    └─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  EventBridge    │────│   SQS Queue      │────│ Event Processor │
│ (Multi-Region)  │    │ (Parallel Proc.) │    │    Lambda       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                       ┌──────────────────┐    ┌─────────────────┐
                       │    Bedrock AI    │────│    DynamoDB     │
                       │ (Risk Analysis)  │    │ (Events/Counts) │
                       └──────────────────┘    └─────────────────┘
```

**Key Components:**
- **CloudFront CDN**: Global content delivery network for fast React app loading
- **React Dashboard**: S3-hosted SPA with Cognito authentication for event visualization
- **Multi-Region EventBridge**: Captures health events from selected AWS regions
- **SQS Queue**: Buffers events for parallel processing with dead letter queue
- **AI Analysis**: Amazon Bedrock analyzes events for risk, impact, and required actions
- **DynamoDB**: Stores processed events with TTL and live count tracking

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