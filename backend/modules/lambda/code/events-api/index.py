import json
import boto3
import os
import logging
from datetime import datetime, timedelta, timezone
from boto3.dynamodb.conditions import Attr, Key

# Set up logging for Lambda
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# Get DynamoDB table name from environment
EVENTS_TABLE_NAME = os.environ.get("DYNAMODB_HEALTH_EVENTS_TABLE_NAME")


def handler(event, context):
    """
    Lambda function for health events endpoints
    Handles notifications, issues, scheduled, and billing events
    """

    try:
        # Log incoming event
        logger.info(
            f"Events API handler invoked with event: {json.dumps(event, default=str)}"
        )

        # Log the request details
        logger.debug(f"Lambda event: {json.dumps(event)}")

        # Handle CORS preflight OPTIONS request
        http_method = event.get("httpMethod", "")
        logger.debug(f"HTTP Method: {http_method}")

        if http_method == "OPTIONS":
            logger.debug("Handling OPTIONS request")
            return {
                "statusCode": 200,
                "headers": {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET,OPTIONS",
                    "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
                },
                "body": "",
            }

        # Ensure we're only processing GET requests (allow blank/null values)
        if http_method and http_method != "GET":
            logger.warning(f"Method not allowed: {http_method}")
            return {
                "statusCode": 405,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET,OPTIONS",
                    "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
                },
                "body": json.dumps(
                    {
                        "error": {
                            "code": "METHOD_NOT_ALLOWED",
                            "message": "Method not allowed",
                        }
                    }
                ),
            }

        # Extract path and query parameters
        path = event.get("path", "")
        path_params = event.get("pathParameters") or {}
        query_params = event.get("queryStringParameters") or {}

        logger.info(f"Processing request for path: {path}")

        # Parse pagination parameters
        limit = int(query_params.get("limit", 50))
        offset = int(query_params.get("offset", 0))
        # Keep next_key for backward compatibility
        next_key = query_params.get("next_key")

        logger.debug(f"Pagination: limit={limit}, offset={offset}")

        # Parse filter IDs - prioritize path parameter over query parameter
        filter_ids = path_params.get("filterId") or query_params.get("filters", "")

        # You can provide account IDs directly, but this is not going to be exposed in API Gateway
        # Keeping this here for testing purposes
        account_filter = query_params.get("accounts")

        # Get account IDs from filters
        filter_account_ids = (
            get_account_ids_from_filters(filter_ids) if filter_ids else []
        )

        if filter_ids:
            logger.debug(
                f"Filter IDs: {filter_ids}, resolved to {len(filter_account_ids)} accounts"
            )

        # Parse direct account parameter
        direct_account_ids = []
        if account_filter:
            if isinstance(account_filter, str):
                try:
                    parsed_accounts = json.loads(account_filter)
                    if isinstance(parsed_accounts, list):
                        direct_account_ids = [
                            acc.strip()
                            for acc in parsed_accounts
                            if acc and acc.strip()
                        ]
                    else:
                        direct_account_ids = [account_filter.strip()]
                except json.JSONDecodeError:
                    direct_account_ids = [
                        acc.strip() for acc in account_filter.split(",") if acc.strip()
                    ]
            elif isinstance(account_filter, list):
                direct_account_ids = [
                    acc.strip() for acc in account_filter if acc and acc.strip()
                ]

        # Combine filter and direct account IDs
        account_ids = list(set(filter_account_ids + direct_account_ids))

        if account_ids:
            logger.info(f"Filtering events for {len(account_ids)} accounts")
        else:
            logger.info("Retrieving events for all accounts")

        # Get events based on endpoint
        if "notifications" in path:
            # GET /events/notifications
            logger.info("Fetching notification events")
            data = get_events_by_category(
                "accountNotification", limit, offset, account_ids
            )
        elif "issues" in path:
            # GET /events/issues
            logger.info("Fetching issue events")
            data = get_events_by_category("issue", limit, offset, account_ids)
        elif "scheduled" in path:
            # GET /events/scheduled
            logger.info("Fetching scheduled events")
            data = get_events_by_category("scheduledChange", limit, offset, account_ids)
        elif "billing" in path:
            # GET /events/billing
            logger.info("Fetching billing events")
            data = get_billing_events(limit, offset, account_ids)
        else:
            logger.error(f"Unknown endpoint: {path}")
            raise ValueError("Unknown endpoint")

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,OPTIONS",
                "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
            },
            "body": json.dumps(data),
        }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET,OPTIONS",
                "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
            },
            "body": json.dumps(
                {
                    "error": {
                        "code": "INTERNAL_ERROR",
                        "message": "An internal server error occurred",
                    }
                }
            ),
        }


def consolidate_events(events):
    """Consolidate events by eventArn"""
    consolidated = {}
    account_names = {}  # Track account names as we process events

    for event in events:
        key = event.get("eventArn", "")
        account_id = event.get("accountId")
        account_name = event.get("accountName")

        # Store account name mapping
        if account_id and account_name:
            account_names[account_id] = account_name

        if key in consolidated:
            # Consolidate account IDs
            if (
                account_id
                and account_id.strip()
                and account_id not in consolidated[key]["accountIds"]
            ):
                consolidated[key]["accountIds"].append(account_id)

            # Consolidate affected resources
            event_resources = event.get("affectedResources", [])
            if event_resources and isinstance(event_resources, list):
                existing_resources = consolidated[key]["affectedResources"]
                for resource in event_resources:
                    if resource and resource not in existing_resources:
                        existing_resources.append(resource)

            # Update with latest event data if this event is newer
            if event.get("lastUpdateTime", "") > consolidated[key].get(
                "lastUpdateTime", ""
            ):
                consolidated[key]["lastUpdateTime"] = event.get("lastUpdateTime")
                consolidated[key]["eventArn"] = event.get(
                    "eventArn"
                )  # Update eventArn with latest
                consolidated[key]["simplifiedDescription"] = event.get(
                    "simplifiedDescription"
                )  # Update simplified description with latest
        else:
            # Initialize affectedResources as a list, ensuring it's always an array
            affected_resources = event.get("affectedResources", [])
            if not isinstance(affected_resources, list):
                affected_resources = [affected_resources] if affected_resources else []

            consolidated[key] = {
                "eventArn": event.get("eventArn"),
                "eventType": event.get("eventType"),
                "service": event.get("service"),
                "region": event.get("region"),
                "riskLevel": event.get("riskLevel"),
                "lastUpdateTime": event.get("lastUpdateTime"),
                "consequencesIfIgnored": event.get("consequencesIfIgnored"),
                "requiredActions": event.get("requiredActions"),
                "impactAnalysis": event.get("impactAnalysis"),
                "riskCategory": event.get("riskCategory"),
                "affectedResources": affected_resources,
                "description": event.get("description"),
                "simplifiedDescription": event.get("simplifiedDescription"),
                "accountIds": [account_id] if account_id and account_id.strip() else [],
            }

    # Transform accountIds from array to object with names, sorted by account name then account ID
    consolidated_list = list(consolidated.values())
    for event in consolidated_list:
        account_ids_with_names = {}
        for account_id in event["accountIds"]:
            account_name = account_names.get(
                account_id, account_id
            )  # Fallback to account_id if name not found
            account_ids_with_names[account_id] = account_name

        # Sort accounts by account name first, then by account ID
        # Convert to list of tuples, sort, then convert back to ordered dict
        sorted_accounts = sorted(
            account_ids_with_names.items(),
            key=lambda x: (
                x[1].lower(),
                x[0],
            ),  # Sort by account name (case-insensitive), then account ID
        )

        # Convert back to dictionary (Python 3.7+ maintains insertion order)
        event["accountIds"] = dict(sorted_accounts)

    return consolidated_list


def get_events_by_category(category, limit=50, offset=0, account_filter=None):
    """
    Get events by category using GSI Query with offset-based pagination

    This function uses the CategoryTimeIndex GSI for efficient querying
    and implements offset-based pagination for better user experience.
    """

    logger.debug(
        f"Querying category '{category}' with limit={limit}, offset={offset}, accounts={len(account_filter) if account_filter else 0}"
    )

    # Early return if table name not configured
    if not EVENTS_TABLE_NAME:
        logger.error("EVENTS_TABLE_NAME not configured")
        return {
            "data": [],
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": 0,
                "has_more": False,
                "current_page": 1,
                "total_pages": 0,
            },
        }

    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(EVENTS_TABLE_NAME)

        # Calculate date filter (180 days ago)
        days_ago = (datetime.now(timezone.utc) - timedelta(days=180)).strftime(
            "%Y-%m-%d"
        )

        # Build query parameters using GSI
        query_kwargs = {
            "IndexName": "CategoryTimeIndex",
            "KeyConditionExpression": Key("eventTypeCategory").eq(category)
            & Key("lastUpdateTime").gte(days_ago),
            "FilterExpression": Attr("statusCode").ne("closed")
            & Attr("service").ne(
                "BILLING"
            ),  # Exclude billing events from all category endpoints
            "ScanIndexForward": False,  # Sort by lastUpdateTime descending (newest first)
            "ProjectionExpression": "eventArn, accountId, accountName, eventType, #r, service, lastUpdateTime, riskLevel, consequencesIfIgnored, requiredActions, impactAnalysis, riskCategory, affectedResources, description, simplifiedDescription",
            "ExpressionAttributeNames": {"#r": "region"},  # 'region' is a reserved word
        }

        # Add account filtering if specified
        if account_filter:
            logger.debug(f"Adding account filter for {len(account_filter)} accounts")
            account_conditions = [Attr("accountId").eq(acc) for acc in account_filter]
            if len(account_conditions) == 1:
                query_kwargs["FilterExpression"] = (
                    query_kwargs["FilterExpression"] & account_conditions[0]
                )
            else:
                from functools import reduce
                import operator

                account_filter_expr = reduce(operator.or_, account_conditions)
                query_kwargs["FilterExpression"] = (
                    query_kwargs["FilterExpression"] & account_filter_expr
                )

        # Query all items for consolidation
        # Note: We need all items because consolidation changes the total count
        all_items = []
        last_evaluated_key = None

        while True:
            if last_evaluated_key:
                query_kwargs["ExclusiveStartKey"] = last_evaluated_key

            response = table.query(**query_kwargs)
            all_items.extend(response.get("Items", []))

            last_evaluated_key = response.get("LastEvaluatedKey")
            if not last_evaluated_key:
                break

        logger.debug(f"Retrieved {len(all_items)} raw items from DynamoDB")

        # Consolidate events (combines similar events across accounts)
        consolidated_events = consolidate_events(all_items)
        consolidated_events.sort(
            key=lambda x: x.get("lastUpdateTime", ""), reverse=True
        )

        logger.debug(f"Consolidated to {len(consolidated_events)} events")

        # Apply offset and limit to consolidated results
        total_consolidated = len(consolidated_events)
        start_idx = offset
        end_idx = offset + limit
        page_events = consolidated_events[start_idx:end_idx]

        # Calculate pagination metadata
        has_more = end_idx < total_consolidated
        total_pages = (
            (total_consolidated + limit - 1) // limit if total_consolidated > 0 else 0
        )  # Ceiling division
        current_page = (offset // limit) + 1 if limit > 0 else 1

        pagination = {
            "limit": limit,
            "offset": offset,
            "total": total_consolidated,
            "has_more": has_more,
            "current_page": current_page,
            "total_pages": total_pages,
        }

        logger.info(
            f"Returning page {current_page} of {total_pages} ({len(page_events)} events)"
        )

        return {"data": page_events, "pagination": pagination}

    except Exception as e:
        logger.error(f"Error querying DynamoDB: {str(e)}")
        import traceback

        logger.error(f"{traceback.format_exc()}")
        return {
            "data": [],
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": 0,
                "has_more": False,
                "current_page": 1,
                "total_pages": 0,
            },
        }


def get_billing_events(limit=50, offset=0, account_filter=None):
    """
    Get billing-related events using scan with offset-based pagination

    Note: Billing events use service="BILLING" filter, so we use scan instead of GSI
    since we don't have a GSI on service field.
    """
    logger.debug(
        f"Querying billing events with limit={limit}, offset={offset}, accounts={len(account_filter) if account_filter else 0}"
    )

    if not EVENTS_TABLE_NAME:
        logger.error("EVENTS_TABLE_NAME not configured")
        return {
            "data": [],
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": 0,
                "has_more": False,
                "current_page": 1,
                "total_pages": 0,
            },
        }

    try:
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(EVENTS_TABLE_NAME)

        days_ago = (datetime.now(timezone.utc) - timedelta(days=180)).strftime(
            "%Y-%m-%d"
        )

        # Build filter expression for billing events
        filter_expression = (
            Attr("service").eq("BILLING")
            & Attr("statusCode").ne("closed")
            & Attr("lastUpdateTime").gte(days_ago)
        )

        # Add account filter if provided
        if account_filter:
            logger.debug(
                f"Adding account filter for {len(account_filter)} accounts to billing query"
            )
            account_conditions = [Attr("accountId").eq(acc) for acc in account_filter]
            if len(account_conditions) == 1:
                filter_expression = filter_expression & account_conditions[0]
            else:
                from functools import reduce
                import operator

                account_filter_expr = reduce(operator.or_, account_conditions)
                filter_expression = filter_expression & account_filter_expr

        # Scan all billing events (since we don't have GSI on service)
        all_events = []
        last_evaluated_key = None

        scan_kwargs = {
            "FilterExpression": filter_expression,
            "ProjectionExpression": "eventArn, accountId, accountName, eventType, #r, service, lastUpdateTime, riskLevel, consequencesIfIgnored, requiredActions, impactAnalysis, riskCategory, affectedResources, description, simplifiedDescription",
            "ExpressionAttributeNames": {"#r": "region"},
        }

        while True:
            if last_evaluated_key:
                scan_kwargs["ExclusiveStartKey"] = last_evaluated_key

            response = table.scan(**scan_kwargs)
            all_events.extend(response.get("Items", []))

            last_evaluated_key = response.get("LastEvaluatedKey")
            if not last_evaluated_key:
                break

        logger.debug(f"Retrieved {len(all_events)} raw billing events from DynamoDB")

        # Consolidate events
        consolidated_events = consolidate_events(all_events)
        consolidated_events.sort(
            key=lambda x: x.get("lastUpdateTime", ""), reverse=True
        )

        logger.debug(f"Consolidated to {len(consolidated_events)} billing events")

        # Apply offset and limit to consolidated results
        total_consolidated = len(consolidated_events)
        start_idx = offset
        end_idx = offset + limit
        page_events = consolidated_events[start_idx:end_idx]

        # Calculate pagination metadata
        has_more = end_idx < total_consolidated
        total_pages = (
            (total_consolidated + limit - 1) // limit if total_consolidated > 0 else 0
        )
        current_page = (offset // limit) + 1 if limit > 0 else 1

        pagination = {
            "limit": limit,
            "offset": offset,
            "total": total_consolidated,
            "has_more": has_more,
            "current_page": current_page,
            "total_pages": total_pages,
        }

        logger.info(
            f"Returning billing page {current_page} of {total_pages} ({len(page_events)} events)"
        )

        return {"data": page_events, "pagination": pagination}

    except Exception as e:
        logger.error(f"Error querying DynamoDB: {str(e)}")
        import traceback

        logger.error(f"{traceback.format_exc()}")
        return {
            "data": [],
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": 0,
                "has_more": False,
                "current_page": 1,
                "total_pages": 0,
            },
        }


def get_account_ids_from_filters(filter_ids_param):
    """Get account IDs from filter IDs by calling filters Lambda individually"""
    if not filter_ids_param:
        return []

    # Parse filter IDs
    filter_ids = []
    if isinstance(filter_ids_param, str):
        try:
            parsed_filters = json.loads(filter_ids_param)
            if isinstance(parsed_filters, list):
                filter_ids = [f.strip() for f in parsed_filters if f and f.strip()]
            else:
                filter_ids = [filter_ids_param.strip()]
        except json.JSONDecodeError:
            filter_ids = [f.strip() for f in filter_ids_param.split(",") if f.strip()]
    elif isinstance(filter_ids_param, list):
        filter_ids = [f.strip() for f in filter_ids_param if f and f.strip()]

    if not filter_ids:
        return []

    try:
        logger.debug(f"Resolving {len(filter_ids)} filter IDs to account IDs")
        lambda_client = boto3.client("lambda")
        filters_function_name = os.environ.get("FILTERS_FUNCTION_NAME")

        if not filters_function_name:
            logger.error("FILTERS_FUNCTION_NAME not set")
            return []

        combined_accounts = set()

        # Only process the first filter ID, ignore the rest
        # in the future if this feature needs to be extended, edit this logic here
        filter_id = filter_ids[0]
        logger.debug(f"Processing filter ID: {filter_id}")
        filter_event = {
            "httpMethod": "GET",
            "path": f"/filters/{filter_id}",
            "pathParameters": {"filterId": filter_id},
        }

        response = lambda_client.invoke(
            FunctionName=filters_function_name,
            InvocationType="RequestResponse",
            Payload=json.dumps(filter_event),
        )

        payload = json.loads(response["Payload"].read())

        if payload.get("statusCode") == 200:
            result = json.loads(payload.get("body", "{}"))
            account_ids = result.get("accountIds", [])
            combined_accounts.update(account_ids)
            logger.debug(f"Filter {filter_id} resolved to {len(account_ids)} accounts")
        else:
            logger.warning(f"Error getting filter {filter_id}: {payload}")

        logger.info(f"Resolved filters to {len(combined_accounts)} unique accounts")
        return list(combined_accounts)

    except Exception as e:
        logger.error(f"Error calling filters Lambda: {str(e)}")
        return []
