# SQS Message Size Fix - Event Keys Pattern

## Problem
The email-processor Lambda was sending full event objects in SQS messages to the account-email-sender Lambda. When accounts had many events or events with large text fields (descriptions, analysis, etc.), the SQS message exceeded the 256 KB limit, causing the error:

```
Error sending SQS message for ccoe_alert@certisgroup.com: An error occurred (InvalidParameterValue) 
when calling the SendMessage operation: One or more parameters are invalid. 
Reason: Message must be shorter than 262144 bytes.
```

## Solution
Implemented the **Event Keys Pattern** - a best practice for handling large payloads in event-driven architectures:

1. **Producer (email-processor)**: Sends only event identifiers (eventArn, accountId) in SQS messages
2. **Consumer (account-email-sender)**: Fetches full event details from DynamoDB using the identifiers

## Changes Made

### 1. email-processor Lambda (`backend/modules/lambda/code/email-processor/index.py`)

#### Modified `consolidate_accounts_by_email()`:
- Changed from storing full `events` to storing only `eventKeys`
- Each event key contains only: `{eventArn, accountId}`
- Significantly reduces message size

#### Modified `send_account_email_messages()`:
- Changed message payload from `events` to `eventKeys`
- Added message size logging for monitoring
- Updated documentation

### 2. account-email-sender Lambda (`backend/modules/lambda/code/account-email-sender/index.py`)

#### Added new function `fetch_events_from_dynamodb()`:
- Fetches full event details using batch_get_item
- Handles batching (100 items per request)
- Implements retry logic for unprocessed keys
- Validates all events were fetched

#### Modified `process_account_email()`:
- Now receives `eventKeys` instead of `events`
- Calls `fetch_events_from_dynamodb()` to get full event data
- Rest of the processing remains unchanged

#### Added environment variable:
- `DYNAMODB_HEALTH_EVENTS_TABLE_NAME`: Table name for fetching events

### 3. Lambda Configuration (`backend/modules/lambda/main.tf`)

#### Updated account-email-sender environment variables:
- Added `DYNAMODB_HEALTH_EVENTS_TABLE_NAME = var.events_table_name`

### 4. IAM Permissions (`backend/modules/iam/main.tf`)

#### Added new policy `account_email_sender_dynamodb`:
- Grants `dynamodb:BatchGetItem` permission
- Grants `dynamodb:GetItem` permission
- Scoped to the events table ARN

## Benefits

1. **Solves the 256 KB limit**: Event keys are tiny compared to full events
2. **Scalable**: Can handle accounts with hundreds or thousands of events
3. **Always current data**: Fetches latest event data from DynamoDB at processing time
4. **Best practice**: Standard pattern for event-driven architectures
5. **Efficient**: Uses batch_get_item for optimal DynamoDB performance

## Message Size Comparison

### Before (Full Events):
```json
{
  "eventKeys": [
    {
      "eventArn": "arn:aws:health:...",
      "accountId": "123456789012",
      "service": "EC2",
      "eventType": "AWS_EC2_INSTANCE_RETIREMENT_SCHEDULED",
      "description": "Very long description...",
      "requiredActions": "Very long actions...",
      "impactAnalysis": "Very long analysis...",
      ... (15+ fields per event)
    }
  ]
}
```
**Size**: ~2-5 KB per event → 500 events = 1-2.5 MB ❌

### After (Event Keys Only):
```json
{
  "eventKeys": [
    {
      "eventArn": "arn:aws:health:...",
      "accountId": "123456789012"
    }
  ]
}
```
**Size**: ~100-150 bytes per event → 500 events = ~75 KB ✅

## Deployment

After deploying these changes:

1. The email-processor will send smaller SQS messages
2. The account-email-sender will fetch event details from DynamoDB
3. No changes to email content or functionality
4. Monitoring logs will show message sizes for verification

## Testing

To verify the fix:
1. Check CloudWatch logs for email-processor: Look for "SQS message size" logs
2. Check CloudWatch logs for account-email-sender: Look for "Fetched X events from DynamoDB"
3. Verify emails are sent successfully for accounts with many events
4. No more "Message must be shorter than 262144 bytes" errors
