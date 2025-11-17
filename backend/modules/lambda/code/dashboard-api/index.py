import json
import boto3
import os
import logging
from datetime import datetime
from botocore.exceptions import ClientError
from decimal import Decimal

# Set up logging for Lambda
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

dynamodb = boto3.resource("dynamodb")
filters_table_name = os.environ.get(
    "DYNAMODB_FILTERS_TABLE", "health-dashboard-filters"
)
filters_table = dynamodb.Table(filters_table_name)
table_name = os.environ.get("DYNAMODB_TABLE", "health-dashboard-counts")
table = dynamodb.Table(table_name)

# Standard CORS headers
CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
}


def handler(event, context):
    try:
        # Log incoming event
        logger.info(
            f"Dashboard API handler invoked with event: {json.dumps(event, default=str)}"
        )

        # Handle CORS preflight OPTIONS request
        http_method = event.get("httpMethod", "")
        logger.debug(f"Received request: {http_method}")
        if http_method == "OPTIONS":
            logger.debug("Handling OPTIONS request")
            return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

        # Get filterId from query parameters
        query_params = event.get("queryStringParameters") or {}
        filter_id = query_params.get("filterId")

        if filter_id:
            logger.info(f"Processing dashboard request with filter: {filter_id}")
        else:
            logger.info("Processing dashboard request for all accounts")

        # Get accountIds from filter if filterId is provided
        accountIds = []
        if filter_id:
            accountIds = get_account_ids_from_filter(filter_id)
            if accountIds is None:
                logger.warning(f"Filter not found: {filter_id}")
                return {
                    "statusCode": 404,
                    "headers": CORS_HEADERS,
                    "body": json.dumps(
                        {
                            "error": {
                                "code": "FILTER_NOT_FOUND",
                                "message": "Filter not found",
                            }
                        }
                    ),
                }
            logger.debug(
                f"Retrieved {len(accountIds)} accounts from filter: {accountIds}"
            )

        totals = {
            "active_issues": 0,
            "billing_changes": 0,
            "notifications": 0,
            "scheduled": 0,
        }

        if accountIds:
            logger.debug(f"Querying counts for {len(accountIds)} specific accounts")
            for account_id in accountIds:
                try:
                    response = table.query(
                        KeyConditionExpression=boto3.dynamodb.conditions.Key(
                            "accountId"
                        ).eq(str(account_id))
                    )
                    for item in response.get("Items", []):
                        totals["active_issues"] += int(item.get("active_issues", 0))
                        totals["billing_changes"] += int(item.get("billing_changes", 0))
                        totals["notifications"] += int(item.get("notifications", 0))
                        totals["scheduled"] += int(item.get("scheduled", 0))
                except ClientError as e:
                    logger.error(
                        f"DynamoDB query error for account {account_id}: {str(e)}"
                    )
                    continue
        else:
            logger.debug("Scanning all accounts for counts")
            try:
                response = table.scan()
                items_processed = 0
                for item in response.get("Items", []):
                    totals["active_issues"] += int(item.get("active_issues", 0))
                    totals["billing_changes"] += int(item.get("billing_changes", 0))
                    totals["notifications"] += int(item.get("notifications", 0))
                    totals["scheduled"] += int(item.get("scheduled", 0))
                    items_processed += 1
                logger.debug(f"Processed counts from {items_processed} account records")
            except ClientError as e:
                logger.error(f"DynamoDB scan error: {str(e)}")

        summary_data = {
            "notifications": totals["notifications"],
            "active_issues": totals["active_issues"],
            "scheduled_events": totals["scheduled"],
            "billing_changes": totals["billing_changes"],
        }

        logger.info(
            f"Dashboard summary: {totals['active_issues']} issues, {totals['notifications']} notifications, {totals['scheduled']} scheduled, {totals['billing_changes']} billing"
        )

        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps(summary_data),
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "INTERNAL_ERROR",
                        "message": "An internal server error occurred",
                    }
                }
            ),
        }


def get_account_ids_from_filter(filter_id):
    """Get account IDs from filter table"""
    try:
        logger.debug(f"Retrieving filter: {filter_id}")
        response = filters_table.get_item(Key={"filterId": filter_id})

        if "Item" not in response:
            logger.debug(f"Filter {filter_id} not found in table")
            return None

        account_ids = response["Item"].get("accountIds", [])
        logger.debug(f"Filter {filter_id} contains {len(account_ids)} accounts")
        return account_ids

    except ClientError as e:
        logger.error(f"Error retrieving filter {filter_id}: {str(e)}")
        return None
