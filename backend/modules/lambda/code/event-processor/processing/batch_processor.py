"""
Batch processing logic for health events
"""

import json
import logging
import os
import traceback
from datetime import datetime, timedelta
from collections import defaultdict
from botocore.exceptions import ClientError

from aws_clients.organizations_client import get_account_name
from aws_clients.health_client import (
    fetch_health_event_details_for_org,
    is_org_view_enabled,
)
from storage.dynamodb_handler import (
    process_single_event,
    store_events_in_dynamodb,
    update_live_counts,
    initialize_live_counts,
)
from utils.helpers import format_time, extract_affected_resources
from utils.event_helpers import expand_events_by_account
from analysis.bedrock_analyzer import analyze_event_with_bedrock, categorize_analysis
from utils.sqs_helpers import send_events_to_sqs

# Import environment variables
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_HEALTH_EVENTS_TABLE_NAME")
COUNTS_TABLE_NAME = os.environ.get("DYNAMODB_COUNTS_TABLE_NAME")


def process_single_event_mode(event, health_client, bedrock_client):
    """
    Process a single event by ARN

    Args:
        event (dict): Lambda event containing event_arn
        health_client: AWS Health client
        bedrock_client: Bedrock client

    Returns:
        dict: Processing result
    """
    single_event_arn = event["event_arn"]
    logging.info(f"Processing single event: {single_event_arn}")

    # Try to extract basic information from the ARN
    arn_parts = single_event_arn.split("/")
    service = arn_parts[1] if len(arn_parts) > 1 else "UNKNOWN"
    event_type_code = arn_parts[2] if len(arn_parts) > 2 else "UNKNOWN"

    # Create a synthetic event with information from the ARN
    synthetic_event = {
        "arn": single_event_arn,
        "eventArn": single_event_arn,
        "eventTypeCode": event_type_code,
        "eventTypeCategory": "issue",
        "service": service,
        "region": os.environ.get("AWS_REGION", "us-east-1"),
        "startTime": datetime.utcnow().isoformat(),
        "lastUpdatedTime": datetime.utcnow().isoformat(),
        "accountId": "N/A",
        "description": f"This is a synthetic event created for analysis of ARN: {single_event_arn}",
    }

    # Try to get more information from the events list
    try:
        use_org_view = is_org_view_enabled()
        logging.info(f"Organization view enabled: {use_org_view}")

        list_filter = {"services": [service]} if service != "UNKNOWN" else {}
        logging.debug(f"Attempting to list events with filter: {list_filter}")

        if use_org_view:
            list_response = health_client.describe_events_for_organization(
                filter=list_filter, maxResults=100
            )
        else:
            list_response = health_client.describe_events(
                filter=list_filter, maxResults=100
            )

        if "events" in list_response:
            for evt in list_response["events"]:
                if evt.get("arn") == single_event_arn:
                    logging.info(
                        "Found event in list, updating synthetic event with real data"
                    )
                    # Handle region - use "global" for events without a specific region
                    event_region = evt.get("region", "")
                    if not event_region or event_region == "":
                        event_region = "global"
                    
                    synthetic_event.update(
                        {
                            "eventTypeCode": evt.get("eventTypeCode", event_type_code),
                            "eventTypeCategory": evt.get("eventTypeCategory", "issue"),
                            "region": event_region,
                            "startTime": evt.get(
                                "startTime", synthetic_event["startTime"]
                            ),
                            "lastUpdatedTime": evt.get(
                                "lastUpdatedTime", synthetic_event["lastUpdatedTime"]
                            ),
                            "service": evt.get("service", service),
                            "statusCode": evt.get("statusCode", "unknown"),
                        }
                    )
                    break
    except Exception as e:
        logging.error(f"Error trying to get event from list: {str(e)}")
        logging.error(f"{traceback.format_exc()}")

    # Try to get affected accounts
    affected_accounts = []
    try:
        if is_org_view_enabled():
            logging.info("Attempting to get affected accounts")
            accounts_response = (
                health_client.describe_affected_accounts_for_organization(
                    eventArn=single_event_arn
                )
            )
            affected_accounts = accounts_response.get("affectedAccounts", [])
            logging.info(f"Found affected accounts: {affected_accounts}")
    except Exception as e:
        logging.error(f"Error getting affected accounts: {str(e)}")

    # Process for each affected account
    events_analysis = []

    if affected_accounts:
        logging.info(f"Processing event for {len(affected_accounts)} affected accounts")
        for account_id in affected_accounts:
            account_event = synthetic_event.copy()
            account_event["accountId"] = account_id
            account_event["accountName"] = get_account_name(account_id)

            # Try to get entity details for this account
            try:
                entities_response = (
                    health_client.describe_affected_entities_for_organization(
                        organizationEntityFilters=[
                            {
                                "eventArn": single_event_arn,
                                "awsAccountId": account_id,
                            }
                        ]
                    )
                )

                entities = entities_response.get("entities", [])
                if entities:
                    affected_resources = ", ".join(
                        [
                            e.get("entityValue", "")
                            for e in entities
                            if e.get("entityValue")
                        ]
                    )
                    account_event["affected_resources"] = (
                        affected_resources if affected_resources else "None specified"
                    )
            except Exception as e:
                logging.error(
                    f"Error getting affected entities for account {account_id}: {str(e)}"
                )

            # Process this account's event
            account_analysis = process_single_event(bedrock_client, account_event)
            if account_analysis:
                events_analysis.extend(account_analysis)
    else:
        # Process as a single event with no specific account
        logging.info("Processing synthetic event with no specific account")
        logging.debug(
            f"Synthetic event data: {json.dumps(synthetic_event, default=str)}"
        )
        single_analysis = process_single_event(bedrock_client, synthetic_event)
        if single_analysis:
            events_analysis.extend(single_analysis)

    # Store the analyzed events in DynamoDB
    if events_analysis:
        logging.info(f"Storing {len(events_analysis)} analyzed events in DynamoDB")
        storage_result = store_events_in_dynamodb(events_analysis)
        counts_result = update_live_counts(events_analysis)

        logging.info(
            f"Single event processing complete: stored={storage_result.get('stored', 0)}, updated={storage_result.get('updated', 0)}"
        )
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "event_arn": single_event_arn,
                    "analyzed_events": len(events_analysis),
                    "affected_accounts": len(affected_accounts),
                    "stored_in_dynamodb": storage_result.get("stored", 0),
                    "updated_in_dynamodb": storage_result.get("updated", 0),
                    "failed_to_store": storage_result.get("failed", 0),
                    "counts_updated": counts_result.get("updated", 0),
                    "synthetic": True,
                }
            ),
        }
    else:
        logging.error(f"Failed to analyze event: {single_event_arn}")
        return {
            "statusCode": 404,
            "body": json.dumps(
                {"error": f"Failed to analyze event: {single_event_arn}"}
            ),
        }


def process_batch_events(health_client, bedrock_client, sqs_client, context, lookback_days=None):
    """
    Process batch of health events

    Args:
        health_client: AWS Health client
        bedrock_client: Bedrock client
        sqs_client: SQS client
        context: Lambda context
        lookback_days: Optional override for analysis window (used by scheduled sync)

    Returns:
        dict: Processing result
    """
    logging.info("Starting batch event processing")

    # Get configuration from environment
    analysis_window_days = lookback_days if lookback_days is not None else int(os.environ["ANALYSIS_WINDOW_DAYS"])
    excluded_services = os.environ.get("EXCLUDED_SERVICES", "").split(",")
    excluded_services = [s.strip() for s in excluded_services if s.strip()]

    logging.info(
        f"Configuration: analysis_window_days={analysis_window_days}, excluded_services={len(excluded_services)}"
    )
    
    if lookback_days is not None:
        logging.info(f"Using scheduled sync mode with {lookback_days} days lookback")

    # Get event categories to process from environment variable
    event_categories_to_process = []
    if "EVENT_CATEGORIES" in os.environ and os.environ["EVENT_CATEGORIES"].strip():
        event_categories_to_process = [
            cat.strip() for cat in os.environ["EVENT_CATEGORIES"].split(",")
        ]
        logging.info(
            f"Will only process these event categories: {event_categories_to_process}"
        )
    else:
        logging.info("No EVENT_CATEGORIES specified, will process all event categories")

    if excluded_services:
        logging.info(f"Excluding services from analysis: {excluded_services}")

    # Set up time range for filtering
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=analysis_window_days)
    logging.info(f"Fetching events between {start_time} and {end_time}")

    # Format dates properly for the API
    formatted_start = start_time.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    formatted_end = end_time.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    # Fetch events from AWS Health
    all_events = []
    try:
        use_org_view = is_org_view_enabled()
        logging.info(f"Organization view enabled: {use_org_view}")

        if use_org_view:
            logging.info("Using AWS Health Organization View")
            all_events = fetch_organization_events(
                health_client,
                formatted_start,
                formatted_end,
                event_categories_to_process,
                context,
            )
        else:
            logging.error("Organization view not enabled")
            return {
                "statusCode": 501,
                "body": json.dumps(
                    {
                        "error": "Please enable Organization Health Dashboard & register a delegated administrator account"
                    }
                ),
            }

    except ClientError as e:
        if e.response["Error"]["Code"] == "SubscriptionRequiredException":
            logging.error(
                "Please enable Organization Health Dashboard & register a delegated administrator account"
            )
            return {
                "statusCode": 501,
                "body": json.dumps(
                    {
                        "error": "Please enable Organization Health Dashboard & register a delegated administrator account"
                    }
                ),
            }
        else:
            raise

    if not all_events:
        logging.warning("No events found in the specified time range")
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "No events found in the specified time range",
                    "events_found": 0,
                }
            ),
        }

    logging.info(f"Retrieved {len(all_events)} events from AWS Health API")

    # Fetch affected accounts for each event and expand
    logging.info(f"Fetching affected accounts for {len(all_events)} events...")
    all_events_with_accounts = []

    for i, event in enumerate(all_events):
        # Check remaining time to avoid timeout
        if context.get_remaining_time_in_millis() < 30000:  # 30 seconds buffer
            logging.warning(
                f"Approaching timeout, processing remaining {len(all_events) - i} events without account fetching"
            )
            # Add remaining events without account fetching
            for remaining_event in all_events[i:]:
                remaining_event["affectedAccounts"] = []
                all_events_with_accounts.append(remaining_event)
            break

        try:
            event_arn = event.get("arn", "")
            if event_arn:
                # Fetch affected accounts for this event
                accounts_response = (
                    health_client.describe_affected_accounts_for_organization(
                        eventArn=event_arn
                    )
                )
                affected_accounts = accounts_response.get("affectedAccounts", [])
                event["affectedAccounts"] = affected_accounts

                if affected_accounts:
                    logging.debug(
                        f"Event {event.get('eventTypeCode', 'unknown')} affects {len(affected_accounts)} accounts"
                    )
                else:
                    logging.debug(
                        f"Event {event.get('eventTypeCode', 'unknown')} has no affected accounts - will be skipped"
                    )
            else:
                logging.warning(
                    f"Event {event.get('eventTypeCode', 'unknown')} has no ARN - will be skipped"
                )
                event["affectedAccounts"] = []

        except Exception as e:
            logging.error(
                f"Error fetching affected accounts for event {event.get('eventTypeCode', 'unknown')}: {str(e)}"
            )
            event["affectedAccounts"] = []

        all_events_with_accounts.append(event)

    # Now expand events by affected accounts
    all_events_expanded = expand_events_by_account(all_events_with_accounts)
    items_count = len(all_events)

    # Check if we should use SQS for parallel processing or process synchronously
    if (
        DYNAMODB_TABLE_NAME and len(all_events_expanded) > 10
    ):  # Use SQS for large batches
        logging.info(
            f"Large batch detected ({len(all_events_expanded)} events), using SQS for parallel processing..."
        )
        return process_with_sqs(
            all_events_expanded, items_count, event_categories_to_process
        )
    else:
        # Synchronous processing mode (for small batches)
        logging.info(
            f"Using synchronous processing mode for {len(all_events_expanded)} events..."
        )
        return process_synchronously(
            all_events_expanded,
            items_count,
            event_categories_to_process,
            bedrock_client,
            context,
        )


def fetch_organization_events(
    health_client, formatted_start, formatted_end, event_categories_to_process, context
):
    """
    Fetch events using organization view
    """
    all_events = []

    # Fetch closed events
    closed_filter = {
        "lastUpdatedTime": {"from": formatted_start, "to": formatted_end},
        "eventStatusCodes": ["closed", "upcoming"],
    }
    if event_categories_to_process:
        closed_filter["eventTypeCategories"] = event_categories_to_process

    logging.info(f"Fetching CLOSED events with filter: {closed_filter}")
    closed_response = health_client.describe_events_for_organization(
        filter=closed_filter, maxResults=100
    )

    if "events" in closed_response:
        all_events.extend(closed_response["events"])
        logging.info(
            f"Retrieved {len(closed_response.get('events', []))} closed events"
        )

    # Handle pagination for closed events
    while "nextToken" in closed_response and closed_response["nextToken"]:
        logging.debug("Found nextToken for closed events, fetching more...")
        if context.get_remaining_time_in_millis() < 15000:
            logging.warning("Approaching Lambda timeout, stopping pagination")
            break

        closed_response = health_client.describe_events_for_organization(
            filter=closed_filter,
            maxResults=100,
            nextToken=closed_response["nextToken"],
        )

        if "events" in closed_response:
            all_events.extend(closed_response["events"])
            logging.debug(
                f"Retrieved {len(closed_response.get('events', []))} additional closed events"
            )

    # Fetch open events
    open_filter = {
        "lastUpdatedTime": {"from": formatted_start},
        "eventStatusCodes": ["open"],
    }
    if event_categories_to_process:
        open_filter["eventTypeCategories"] = event_categories_to_process

    logging.info(f"Fetching OPEN events with filter: {open_filter}")
    open_response = health_client.describe_events_for_organization(
        filter=open_filter, maxResults=100
    )

    if "events" in open_response:
        all_events.extend(open_response["events"])
        logging.info(f"Retrieved {len(open_response.get('events', []))} open events")

    # Handle pagination for open events
    while "nextToken" in open_response and open_response["nextToken"]:
        logging.debug("Found nextToken for open events, fetching more...")
        if context.get_remaining_time_in_millis() < 15000:
            logging.warning("Approaching Lambda timeout, stopping pagination")
            break

        open_response = health_client.describe_events_for_organization(
            filter=open_filter,
            maxResults=100,
            nextToken=open_response["nextToken"],
        )

        if "events" in open_response:
            all_events.extend(open_response["events"])
            logging.debug(
                f"Retrieved {len(open_response.get('events', []))} additional open events"
            )

    return all_events


def process_with_sqs(all_events_expanded, items_count, event_categories_to_process):
    """
    Process events using SQS for parallel processing
    """
    # Filter events by category before sending to SQS
    events_to_process = []
    filtered_count = 0

    for item in all_events_expanded:
        # Check if we should process this event category
        event_type_category = item.get("eventTypeCategory", "")

        if (
            event_categories_to_process
            and event_type_category not in event_categories_to_process
        ):
            logging.debug(
                f"Skipping event {item.get('eventTypeCode', 'unknown')} with category {event_type_category} (not in configured categories)"
            )
            filtered_count += 1
            continue

        # Skip events without valid account ID early
        account_id = item.get("accountId", "N/A")
        if account_id == "N/A" or not account_id:
            logging.debug(
                f"Skipping event {item.get('eventTypeCode', 'unknown')} - no valid account ID"
            )
            filtered_count += 1
            continue

        # Ensure we have the event ARN and standardize field name
        event_arn = item.get("arn", "")
        if event_arn:
            item["eventArn"] = event_arn

        events_to_process.append(item)

    logging.info(
        f"Sending {len(events_to_process)} events to SQS for parallel processing (filtered out {filtered_count})"
    )

    # Send events to SQS for parallel processing
    sqs_result = send_events_to_sqs(events_to_process)

    if sqs_result.get("fallback", False):
        logging.warning("SQS not available, falling back to synchronous processing...")
        # Would need to implement fallback logic here
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "SQS fallback not implemented"}),
        }
    else:
        # Return SQS batch processing result
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "mode": "sqs_parallel_processing",
                    "total_events": items_count,
                    "total_expanded_events": len(all_events_expanded),
                    "events_sent_to_sqs": sqs_result["sent"],
                    "events_failed_to_send": sqs_result["failed"],
                    "filtered_events": filtered_count,
                    "message": f"Sent {sqs_result['sent']} events to SQS for parallel processing",
                }
            ),
        }


def process_synchronously(
    all_events_expanded,
    items_count,
    event_categories_to_process,
    bedrock_client,
    context,
):
    """
    Process events synchronously (for small batches)
    """
    events_analysis = []
    event_categories = defaultdict(int)
    filtered_count = 0

    # Process each event from the expanded API results
    for item in all_events_expanded:
        if context.get_remaining_time_in_millis() > 10000:
            # Check if we should process this event category
            event_type_category = item.get("eventTypeCategory", "")

            if (
                event_categories_to_process
                and event_type_category not in event_categories_to_process
            ):
                logging.debug(
                    f"Skipping event {item.get('eventTypeCode', 'unknown')} with category {event_type_category} (not in configured categories)"
                )
                filtered_count += 1
                continue

            logging.debug(
                f"Processing event: {item.get('eventTypeCode', 'unknown')} with category {event_type_category}"
            )

            try:
                # Ensure we have the event ARN and standardize field name
                event_arn = item.get("arn", "")
                if event_arn:
                    item["eventArn"] = event_arn

                # Extract account ID from ARN
                account_id = item.get("accountId", "N/A")

                # Skip events without valid account ID early to save processing time
                if account_id == "N/A" or not account_id:
                    logging.debug(
                        f"Skipping event {item.get('eventTypeCode', 'unknown')} - no valid account ID"
                    )
                    filtered_count += 1
                    continue

                logging.debug(f"Processing with account ID: {account_id}")

                # Get account name
                account_name = get_account_name(account_id)

                # Fetch additional details from Health API
                health_data = fetch_health_event_details_for_org(
                    item.get("arn", ""), account_id
                )

                # Extract the actual description for analysis
                actual_description = (
                    health_data["details"]
                    .get("eventDescription", {})
                    .get("latestDescription", "")
                )

                if not actual_description:
                    actual_description = (
                        item.get("eventDescription", "")
                        or item.get("description", "")
                        or item.get("message", "")
                        or "No description available"
                    )

                logging.debug(
                    f"Using description (length: {len(actual_description)}): {actual_description[:100]}..."
                )

                # Update the item with the actual description to improve analysis
                item_with_description = item.copy()
                item_with_description["description"] = actual_description

                analysis = analyze_event_with_bedrock(
                    bedrock_client, item_with_description
                )

                categories = categorize_analysis(analysis)
                if categories.get("critical", False):
                    event_categories["critical"] += 1

                risk_level = categories.get("risk_level", "LOW")
                event_categories[f"{risk_level}_risk"] += 1

                account_impact = categories.get("account_impact", "low")
                event_categories[f"{account_impact}_impact"] += 1

                # Handle region - use "global" for events without a specific region
                item_region = item.get("region", "")
                if not item_region or item_region == "":
                    item_region = "global"
                
                # Create structured event data with both raw data and analysis
                event_entry = {
                    "arn": item.get("arn", "N/A"),
                    "eventArn": item.get("eventArn", item.get("arn", "N/A")),
                    "event_type": item.get("eventTypeCode", "N/A"),
                    "service": item.get("service", "N/A"),
                    "description": actual_description,
                    "region": item_region,
                    "start_time": format_time(item.get("startTime", "N/A")),
                    "last_update_time": format_time(item.get("lastUpdatedTime", "N/A")),
                    "status_code": item.get("statusCode", "unknown"),
                    "event_type_category": item.get("eventTypeCategory", "N/A"),
                    "analysis_text": analysis,
                    "critical": categories.get("critical", False),
                    "risk_level": categories.get("risk_level", "LOW"),
                    "accountId": account_id,
                    "accountName": account_name,
                    "impact_analysis": categories.get("impact_analysis", ""),
                    "required_actions": categories.get("required_actions", ""),
                    "time_sensitivity": categories.get("time_sensitivity", "Routine"),
                    "risk_category": categories.get("risk_category", "Unknown"),
                    "consequences_if_ignored": categories.get(
                        "consequences_if_ignored", ""
                    ),
                    "affected_resources": extract_affected_resources(
                        health_data["entities"]
                    ),
                    "event_impact_type": categories.get("event_impact_type", "Unknown"),
                }

                events_analysis.append(event_entry)
                logging.debug(f"Successfully analyzed event {len(events_analysis)}")
            except Exception as e:
                logging.error(f"Error analyzing event: {str(e)}")
                logging.error(f"{traceback.format_exc()}")
        else:
            logging.warning("Approaching Lambda timeout, stopping event processing")
            break

    if events_analysis:
        logging.info(
            f"Successfully analyzed {len(events_analysis)} events (filtered out {filtered_count} events)"
        )

        # Check if we should store in DynamoDB
        if DYNAMODB_TABLE_NAME:
            logging.info(f"DynamoDB table name provided: {DYNAMODB_TABLE_NAME}")
            logging.info("Storing events in DynamoDB")

            # Store events in DynamoDB
            storage_result = store_events_in_dynamodb(events_analysis)

            # Update live counts with current events
            logging.info(f"Updating live counts for {len(events_analysis)} events")
            counts_result = update_live_counts(events_analysis)

            # Check if we need to initialize live counts from existing events (first deployment)
            if COUNTS_TABLE_NAME:
                try:
                    import boto3

                    dynamodb = boto3.resource("dynamodb")
                    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)

                    # Check if table is empty (indicates first deployment)
                    response = counts_table.scan(Limit=1)
                    if response.get("Count", 0) == 0:
                        logging.warning(
                            "Counts table is empty after processing current events"
                        )
                        logging.warning(
                            "This might indicate an issue with the live counts update"
                        )
                        logging.info(
                            "Attempting to initialize from existing open events in events table"
                        )
                        initialize_live_counts()
                    else:
                        logging.info(
                            f"Counts table now has {response.get('Count', 0)} records"
                        )
                except Exception as e:
                    logging.error(f"Error checking counts table after update: {str(e)}")
                    logging.error(f"{traceback.format_exc()}")

            return {
                "statusCode": 200,
                "body": json.dumps(
                    {
                        "total_events": items_count,
                        "total_expanded_events": len(all_events_expanded),
                        "analyzed_events": len(events_analysis),
                        "filtered_events": filtered_count,
                        "stored_in_dynamodb": storage_result["stored"],
                        "updated_in_dynamodb": storage_result.get("updated", 0),
                        "failed_to_store": storage_result["failed"],
                        "counts_updated": counts_result.get("updated", 0),
                        "categories": dict(event_categories),
                    }
                ),
            }
        else:
            return {
                "statusCode": 500,
                "body": json.dumps(
                    {
                        "error": "DynamoDB table name not configured",
                        "analyzed_events": len(events_analysis),
                    }
                ),
            }
    else:
        logging.warning(
            f"No events were successfully analyzed (filtered out {filtered_count} events)"
        )
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Found events but none were analyzed",
                    "events_found": items_count,
                    "filtered_events": filtered_count,
                    "category_filter_applied": bool(event_categories_to_process),
                    "categories_processed": event_categories_to_process,
                }
            ),
        }
