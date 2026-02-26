import boto3
import json
import logging
import os
import traceback
from datetime import datetime, timedelta
from decimal import Decimal
from botocore.exceptions import ClientError

from utils.config import DYNAMODB_TABLE_NAME, COUNTS_TABLE_NAME
from utils.helpers import format_date_only, format_datetime, extract_affected_resources
from aws_clients.organizations_client import get_account_name
from aws_clients.health_client import fetch_health_event_details_for_org
from analysis.bedrock_analyzer import analyze_event_with_bedrock, categorize_analysis


def _parse_timestamp(timestamp_input):
    """
    Parse a timestamp string into a naive UTC datetime.

    Handles ISO format (with/without Z suffix) and RFC 2822 format.

    Args:
        timestamp_input (str): Timestamp string to parse

    Returns:
        datetime: Naive UTC datetime, or None if input is invalid/empty
    """
    if not timestamp_input or timestamp_input == "N/A":
        return None

    try:
        if timestamp_input.endswith("Z"):
            dt = datetime.fromisoformat(timestamp_input.replace("Z", "+00:00"))
        elif "GMT" in timestamp_input or "," in timestamp_input:
            from email.utils import parsedate_to_datetime
            dt = parsedate_to_datetime(timestamp_input)
        else:
            dt = datetime.fromisoformat(timestamp_input)

        # Convert to naive UTC
        if dt.tzinfo is not None:
            dt = datetime(*dt.utctimetuple()[:6])

        return dt
    except Exception:
        return None


def normalize_and_calculate_ttl(last_update_time_input, start_time_input=None):
    """
    Normalize lastUpdateTime and calculate TTL timestamp, keeping both fields in sync

    TTL is calculated from whichever is later: lastUpdateTime or startTime.
    This ensures events with future start dates (e.g. scheduled maintenance)
    are not prematurely expired by DynamoDB TTL before their start date arrives.

    Args:
        last_update_time_input (str): ISO format timestamp string from AWS Health API
        start_time_input (str, optional): Event start time. If the start time is in
            the future relative to lastUpdateTime, TTL will be based on startTime instead.

    Returns:
        tuple: (normalized_last_update_time_iso, ttl_unix_timestamp)
            - normalized_last_update_time_iso: Clean ISO format for storage
            - ttl_unix_timestamp: Unix timestamp for DynamoDB TTL (configurable days later)
    """
    try:
        last_update_dt = _parse_timestamp(last_update_time_input)
        if last_update_dt is None:
            last_update_dt = datetime.utcnow()

        # Normalize to ISO format for consistent storage
        normalized_iso = last_update_dt.isoformat()

        # Determine TTL base: use the later of lastUpdateTime and startTime
        # This protects future-dated events from premature TTL expiry
        ttl_base_dt = last_update_dt
        start_dt = _parse_timestamp(start_time_input)
        if start_dt is not None and start_dt > last_update_dt:
            ttl_base_dt = start_dt
            logging.debug(
                f"TTL based on startTime ({start_dt.isoformat()}) instead of "
                f"lastUpdateTime ({last_update_dt.isoformat()}) - event has future start date"
            )

        # Calculate TTL: configurable days from the TTL base date
        ttl_days = int(os.environ.get("EVENTS_TABLE_TTL_DAYS", "180"))
        ttl_date = ttl_base_dt + timedelta(days=ttl_days)
        ttl_unix = int(ttl_date.timestamp())

        return normalized_iso, ttl_unix

    except Exception as e:
        logging.error(f"Error normalizing timestamp and calculating TTL: {str(e)}")
        logging.debug(f"Input was: last_update={last_update_time_input}, start_time={start_time_input}")

        # Fallback: use current time
        fallback_dt = datetime.utcnow()
        fallback_iso = fallback_dt.isoformat()
        ttl_days = int(os.environ.get("EVENTS_TABLE_TTL_DAYS", "180"))
        fallback_ttl = int((fallback_dt + timedelta(days=ttl_days)).timestamp())

        return fallback_iso, fallback_ttl


def calculate_ttl_timestamp(last_update_time):
    """
    Legacy function for backward compatibility
    Calculate TTL timestamp (configurable days from last update time)

    Args:
        last_update_time (str): ISO format timestamp string

    Returns:
        int: Unix timestamp for TTL (configurable days from last update)
    """
    _, ttl_timestamp = normalize_and_calculate_ttl(last_update_time)
    return ttl_timestamp


def generate_simplified_description(service, event_type_code):
    """
    Generate a simplified/readable event description based on event type rules

    Args:
        service (str): AWS service name
        event_type_code (str): Event type code from AWS Health

    Returns:
        str: Simplified description following the mapping rules
    """
    if not service or service == "N/A":
        service = "AWS"

    # Convert event type to uppercase for consistent matching
    event_type_upper = event_type_code.upper() if event_type_code else ""

    # Apply mapping rules based on event type
    if "OPERATIONAL_ISSUE" in event_type_upper:
        return f"{service} - Service disruptions or performance problems"
    elif "SECURITY_NOTIFICATION" in event_type_upper:
        return f"{service} - Security-related alerts and warnings"
    elif "PLANNED_LIFECYCLE_EVENT" in event_type_upper:
        return f"{service} - Lifecycle changes requiring action"
    elif any(
        keyword in event_type_upper
        for keyword in [
            "MAINTENANCE_SCHEDULED",
            "SYSTEM_MAINTENANCE",
            "PATCHING_RETIREMENT",
        ]
    ):
        return f"{service} - Routine Maintenance"
    elif "UPDATE_AVAILABLE" in event_type_upper:
        return f"{service} - Available software or system updates"
    elif "VPN_CONNECTIVITY" in event_type_upper:
        return "VPN tunnel or connection status alert"
    elif "BILLING_NOTIFICATION" in event_type_upper:
        return f"{service} - Billing or Cost change notification"
    else:
        # Default case for anything else
        return f"{service} - Service-specific events"


def store_events_in_dynamodb(events_analysis):
    """
    Store analyzed events in DynamoDB table

    Args:
        events_analysis (list): List of analyzed events data

    Returns:
        dict: Summary of storage operation
    """
    if not DYNAMODB_TABLE_NAME:
        logging.warning("DynamoDB table name not provided, skipping storage")
        return {"stored": 0, "failed": 0, "updated": 0}

    logging.info(
        f"Storing {len(events_analysis)} events in DynamoDB table: {DYNAMODB_TABLE_NAME}"
    )

    # Create DynamoDB resource
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    # Track success and failures
    stored_count = 0
    failed_count = 0
    updated_count = 0

    # Get current timestamp for metadata in YYYY-MM-DD HH:MM:SS format
    analysis_timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')

    # Process each event
    for event in events_analysis:
        try:
            # Get primary key values
            event_arn = event.get("eventArn", event.get("arn", ""))
            account_id = event.get("accountId", "N/A")

            if not event_arn:
                logging.warning("Skipping event with no ARN")
                failed_count += 1
                continue

            # Skip events without valid account ID
            if account_id == "N/A" or not account_id:
                logging.warning(f"Skipping event {event_arn} with no valid account ID")
                failed_count += 1
                continue

            # Generate simplified description based on service and event type
            simplified_description = generate_simplified_description(
                event.get("service", "N/A"), event.get("event_type", "N/A")
            )

            # Normalize lastUpdateTime and calculate TTL (keeping both fields in sync)
            # Pass start_time so future-dated events aren't prematurely expired
            normalized_last_update_time, ttl_timestamp = normalize_and_calculate_ttl(
                event.get("last_update_time", "N/A"),
                start_time_input=event.get("start_time", None)
            )

            # Create item with all relevant fields
            item = {
                "eventArn": event_arn,
                "accountId": account_id,
                "eventType": event.get("event_type", "N/A"),
                "eventTypeCategory": event.get("event_type_category", "N/A"),
                "region": event.get("region", "N/A"),
                "service": event.get("service", "N/A"),
                "startTime": event.get("start_time", "N/A"),
                "lastUpdateTime": normalized_last_update_time,
                "statusCode": event.get("status_code", "unknown"),
                "description": event.get("description", "N/A"),
                "simplifiedDescription": simplified_description,
                "critical": event.get("critical", False),
                "riskLevel": event.get("risk_level", "LOW"),
                "accountName": event.get("accountName", "N/A"),
                "timeSensitivity": event.get("time_sensitivity", "Routine"),
                "riskCategory": event.get("risk_category", "Unknown"),
                "eventImpactType": event.get("event_impact_type", "Informational"),
                "requiredActions": event.get("required_actions", ""),
                "impactAnalysis": event.get("impact_analysis", ""),
                "consequencesIfIgnored": event.get("consequences_if_ignored", ""),
                "affectedResources": event.get("affected_resources", "None specified"),
                "analysisTimestamp": analysis_timestamp,
                "analysisVersion": "1.0",
                "ttl": ttl_timestamp,
            }

            # Convert any empty strings to None (null in DynamoDB)
            # Keep "N/A" as a string value to avoid NULL in DynamoDB for optional fields
            for key, value in item.items():
                if value == "":
                    item[key] = None

            # Handle decimal conversion for numeric values
            item = json.loads(json.dumps(item), parse_float=Decimal)

            # Check if the item already exists
            try:
                response = table.get_item(
                    Key={"eventArn": event_arn, "accountId": account_id}
                )

                if "Item" in response:
                    logging.info(
                        f"Event {event_arn} for account {account_id} already exists, updating..."
                    )
                    table.put_item(Item=item)
                    updated_count += 1
                else:
                    table.put_item(Item=item)
                    stored_count += 1
            except Exception as e:
                logging.error(f"Error checking for existing item: {str(e)}")
                table.put_item(Item=item)
                stored_count += 1

        except Exception as e:
            logging.error(f"Error storing event in DynamoDB: {str(e)}")
            logging.error(f"{traceback.format_exc()}")
            failed_count += 1

    logging.info(
        f"DynamoDB storage complete: {stored_count} stored, {updated_count} updated, {failed_count} failed"
    )
    return {"stored": stored_count, "updated": updated_count, "failed": failed_count}


def process_single_event(bedrock_client, event_data):
    """
    Process a single event for analysis and DynamoDB storage

    Args:
        bedrock_client: Amazon Bedrock client
        event_data (dict): Event data to process

    Returns:
        list: List containing the analyzed event data or empty list if processing failed
    """
    try:

        # Get account ID and name
        account_id = event_data.get("accountId", "N/A")
        account_name = get_account_name(account_id) if account_id != "N/A" else "N/A"

        # Check if event already exists in DynamoDB with VALID analysis
        event_arn = event_data.get("arn", "")
        existing_event = None
        skip_bedrock_analysis = False
        
        if event_arn and account_id != "N/A" and DYNAMODB_TABLE_NAME:
            try:
                dynamodb = boto3.resource("dynamodb")
                table = dynamodb.Table(DYNAMODB_TABLE_NAME)
                
                response = table.get_item(
                    Key={
                        "eventArn": event_arn,
                        "accountId": account_id
                    }
                )
                
                if "Item" in response:
                    existing_event = response["Item"]
                    
                    # Check if event has VALID analysis
                    # Run Bedrock analysis if:
                    # 1. Failed analysis (specific fallback values)
                    # 2. Missing/blank/null values in key fields
                    
                    # Import default values from bedrock_analyzer
                    from analysis.bedrock_analyzer import DEFAULT_ANALYSIS_VALUES
                    
                    required_actions = existing_event.get("requiredActions", "")
                    risk_category = existing_event.get("riskCategory", "")
                    impact_analysis = existing_event.get("impactAnalysis", "")
                    
                    # Check for failed analysis (Bedrock couldn't analyze)
                    # Compare against the default fallback values
                    is_failed_analysis = (
                        required_actions == DEFAULT_ANALYSIS_VALUES["required_actions"] and
                        risk_category == DEFAULT_ANALYSIS_VALUES["risk_category"] and
                        impact_analysis == DEFAULT_ANALYSIS_VALUES["impact_analysis"]
                    )
                    
                    # Check for missing/blank/null values
                    has_blank_or_null = (
                        not required_actions or required_actions.strip() == "" or
                        not risk_category or risk_category.strip() == "" or
                        not impact_analysis or impact_analysis.strip() == ""
                    )
                    
                    # Valid analysis = has all fields populated AND not failed analysis
                    has_valid_analysis = (
                        required_actions and required_actions.strip() and
                        risk_category and risk_category.strip() and
                        impact_analysis and impact_analysis.strip() and
                        not is_failed_analysis
                    )
                    
                    if has_valid_analysis:
                        skip_bedrock_analysis = True
                        logging.info(f"Event {event_arn} has valid analysis, skipping Bedrock re-analysis")
                    elif is_failed_analysis:
                        logging.info(f"Event {event_arn} has failed analysis (fallback values), will retry with Bedrock")
                    elif has_blank_or_null:
                        logging.info(f"Event {event_arn} has blank/null analysis fields, will analyze with Bedrock")
                    else:
                        logging.info(f"Event {event_arn} exists but incomplete analysis, will analyze")
                else:
                    logging.info(f"Event {event_arn} is new, will analyze")
                    
            except Exception as e:
                logging.warning(f"Error checking for existing event: {str(e)}, will proceed with analysis")

        # Fetch additional details from Health API if needed
        if account_id != "N/A":
            health_data = fetch_health_event_details_for_org(
                event_data.get("arn", ""), account_id
            )

            # Extract affected resources
            affected_resources = extract_affected_resources(
                health_data.get("entities", [])
            )

            # Check if we have a better description from the health data
            health_description = (
                health_data.get("details", {})
                .get("eventDescription", {})
                .get("latestDescription", "")
            )
            if health_description:
                event_data["description"] = health_description
        else:
            affected_resources = "None specified"

        # Make sure we have a description
        if not event_data.get("description"):
            event_data["description"] = "No description available"

        # Analyze the event with Bedrock (or reuse existing valid analysis)
        if skip_bedrock_analysis and existing_event:
            # Reuse existing valid analysis
            # Use impactAnalysis as the analysis text since analysisText doesn't exist in schema
            logging.info("Reusing existing valid Bedrock analysis")
            analysis = existing_event.get("impactAnalysis", "")
            categories = {
                "critical": existing_event.get("critical", False),
                "risk_level": existing_event.get("riskLevel", "LOW"),
                "impact_analysis": existing_event.get("impactAnalysis", ""),
                "required_actions": existing_event.get("requiredActions", ""),
                "time_sensitivity": existing_event.get("timeSensitivity", "Routine"),
                "risk_category": existing_event.get("riskCategory", "Unknown"),
                "consequences_if_ignored": existing_event.get("consequencesIfIgnored", ""),
                "event_impact_type": existing_event.get("eventImpactType", "Unknown"),
            }
        
        # Perform new Bedrock analysis if needed
        if not skip_bedrock_analysis:
            # Perform new Bedrock analysis (for new events or failed analyses)
            if existing_event:
                logging.info("Performing new Bedrock analysis to fix failed/empty analysis")
            else:
                logging.info("Performing Bedrock analysis for new event")
            analysis = analyze_event_with_bedrock(bedrock_client, event_data)
            # Categorize the analysis
            categories = categorize_analysis(analysis)

        # Generate simplified description
        simplified_description = generate_simplified_description(
            event_data.get("service", "N/A"), event_data.get("eventTypeCode", "N/A")
        )

        # Handle region - use "global" for events without a specific region
        event_region = event_data.get("region", "")
        if not event_region or event_region == "":
            event_region = "global"
        
        # Create structured event data
        event_entry = {
            "arn": event_data.get("arn", "N/A"),
            "eventArn": event_data.get("arn", "N/A"),
            "event_type": event_data.get("eventTypeCode", "N/A"),
            "description": event_data.get("description", "N/A"),
            "simplified_description": simplified_description,
            "region": event_region,
            "start_time": format_date_only(event_data.get("startTime", "N/A")),
            "last_update_time": format_datetime(event_data.get("lastUpdatedTime", "N/A")),
            "event_type_category": event_data.get("eventTypeCategory", "N/A"),
            "service": event_data.get("service", "N/A"),
            "status_code": event_data.get(
                "statusCode", "unknown"
            ),  # Add missing status_code field
            "analysis_text": analysis,
            "critical": categories.get("critical", False),
            "risk_level": categories.get("risk_level", "LOW"),
            "accountId": account_id,
            "accountName": account_name,
            "impact_analysis": categories.get("impact_analysis", ""),
            "required_actions": categories.get("required_actions", ""),
            "time_sensitivity": categories.get("time_sensitivity", "Routine"),
            "risk_category": categories.get("risk_category", "Unknown"),
            "consequences_if_ignored": categories.get("consequences_if_ignored", ""),
            "affected_resources": affected_resources,
            "event_impact_type": categories.get("event_impact_type", "Unknown"),
        }

        return [event_entry]

    except Exception as e:
        logging.error(f"Error processing single event: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return []


def update_live_counts(events_analysis, is_sqs_processing=False):
    """
    Update live counts in the counts table based on event status changes

    Args:
        events_analysis (list): List of analyzed events
        is_sqs_processing (bool): True if called from SQS processing (treat as new events)

    Returns:
        dict: Summary of count updates
    """
    logging.info(f"Updating live counts for {len(events_analysis)} events")

    if not COUNTS_TABLE_NAME:
        logging.error("Counts table name not provided, skipping count updates")
        return {"updated": 0, "failed": 0}

    # Create DynamoDB resources
    dynamodb = boto3.resource("dynamodb")
    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)
    events_table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    # Track updates by account
    account_updates = {}

    # Process each event to detect status changes
    for i, event in enumerate(events_analysis):
        account_id = event.get("accountId", "N/A")
        event_arn = event.get("eventArn", event.get("arn", ""))

        # Skip events without valid account ID or ARN
        if account_id == "N/A" or not account_id or not event_arn:
            continue

        # Initialize account counters if needed
        if account_id not in account_updates:
            account_updates[account_id] = {
                "notifications": 0,
                "active_issues": 0,
                "scheduled": 0,
                "billing_changes": 0,
            }

        service = event.get("service", "").upper()
        event_type_category = event.get("event_type_category", "")
        current_status = event.get("status_code", "")

        # Get the previous status from the events table
        previous_status = None

        # Check if this is a force count (from initialization)
        force_count = event.get("force_count", False)

        # Get previous status from DynamoDB for both SQS and batch processing
        # This enables proper status transition counting for all event sources
        if not force_count:
            try:
                response = events_table.get_item(
                    Key={"eventArn": event_arn, "accountId": account_id}
                )
                if "Item" in response:
                    previous_status = response["Item"].get("statusCode", "")
                    if is_sqs_processing:
                        logging.debug(
                            f"SQS processing: Found existing event {event_arn} with previous status '{previous_status}', current status '{current_status}'"
                        )
                else:
                    previous_status = None
                    if is_sqs_processing:
                        logging.debug(
                            f"SQS processing: New event {event_arn} with status '{current_status}'"
                        )
            except Exception as e:
                logging.error(
                    f"Error getting previous status for {event_arn}: {str(e)}"
                )
                previous_status = None
        else:
            previous_status = None

        # Determine what counter category this event belongs to
        counter_category = None
        if service == "BILLING":
            counter_category = "billing_changes"
        elif event_type_category == "accountNotification":
            counter_category = "notifications"
        elif event_type_category == "issue" and service != "BILLING":
            counter_category = "active_issues"
        elif event_type_category == "scheduledChange":
            counter_category = "scheduled"

        # Skip if we can't categorize the event
        if not counter_category:
            continue

        # Calculate the change needed based on status transition
        change_value = 0

        # Check if this is a forced count (from initialization)
        force_count = event.get("force_count", False)

        if force_count:
            # Force count during initialization - ignore previous status
            if current_status == "open":
                change_value = 1
            elif current_status in ["upcoming", "scheduled"]:
                change_value = 1
        elif previous_status is None:
            # Handle initial deployment case (no previous status)
            # For new events, count them if they are open/active
            if current_status == "open":
                change_value = 1
            elif current_status in ["upcoming", "scheduled"]:
                change_value = 1
        else:
            # Handle status changes for existing events
            if previous_status != current_status:
                # Handle transitions - count open, upcoming, and scheduled as active
                active_statuses = ["open", "upcoming", "scheduled"]

                previous_was_active = previous_status in active_statuses
                current_is_active = current_status in active_statuses

                if not previous_was_active and current_is_active:
                    # Event became active (open/upcoming/scheduled): +1
                    change_value = 1
                elif previous_was_active and not current_is_active:
                    # Event was closed/resolved: -1
                    change_value = -1
                # If both are active or both are inactive, no change needed

        # Apply the change
        if change_value != 0:
            account_updates[account_id][counter_category] += change_value

    # Update counts in DynamoDB with safeguards
    updated_count = 0
    failed_count = 0

    for account_id, updates in account_updates.items():
        try:
            # Always ensure all counter categories exist with default 0 values
            # Even if no updates, we want to initialize missing counters
            should_update = any(value != 0 for value in updates.values())

            # Check if account record exists and has all required counters
            needs_initialization = False
            try:
                current_response = counts_table.get_item(Key={"accountId": account_id})
                current_item = current_response.get("Item", {})

                # Check if any required counters are missing
                required_counters = [
                    "notifications",
                    "active_issues",
                    "scheduled",
                    "billing_changes",
                ]
                for counter in required_counters:
                    if counter not in current_item:
                        needs_initialization = True
                        break

            except Exception as e:
                logging.error(
                    f"Error checking existing counters for {account_id}: {str(e)}"
                )
                needs_initialization = True

            # Skip only if no updates AND all counters already exist
            if not should_update and not needs_initialization:
                continue

            # Build atomic update expression using ADD and SET operations
            add_parts = []
            set_parts = []
            expression_values = {}

            # Separate positive and negative updates for different handling
            positive_updates = {k: v for k, v in updates.items() if v > 0}
            negative_updates = {k: v for k, v in updates.items() if v < 0}

            # Handle positive updates with ADD (atomic increment)
            for counter, change_value in positive_updates.items():
                add_parts.append(f"{counter} :val_{counter}")
                expression_values[f":val_{counter}"] = change_value

            # Handle negative updates with conditional SET to prevent negative values
            if negative_updates:
                # First, get current values to calculate safe decrements
                try:
                    current_response = counts_table.get_item(
                        Key={"accountId": account_id}
                    )
                    current_item = current_response.get("Item", {})

                    for counter, change_value in negative_updates.items():
                        current_value = current_item.get(counter, 0)
                        # Calculate new value, ensuring it doesn't go below 0
                        new_value = max(
                            0, current_value + change_value
                        )  # change_value is negative
                        set_parts.append(f"{counter} = :val_{counter}")
                        expression_values[f":val_{counter}"] = new_value

                except Exception as e:
                    logging.error(
                        f"Error getting current counts for negative updates: {str(e)}"
                    )
                    # If we can't get current values, skip negative updates to be safe
                    logging.warning(
                        f"Skipping negative updates for account {account_id} to prevent data corruption"
                    )
                    negative_updates = {}

            # Ensure all counter categories are initialized to 0 if they don't exist
            # This guarantees that every account record has all counter fields
            if needs_initialization:
                required_counters = [
                    "notifications",
                    "active_issues",
                    "scheduled",
                    "billing_changes",
                ]

                # Get current item to check which counters are missing
                try:
                    current_response = counts_table.get_item(
                        Key={"accountId": account_id}
                    )
                    current_item = current_response.get("Item", {})
                except Exception as e:
                    current_item = {}

                # Initialize missing counters to 0
                for counter in required_counters:
                    if counter not in current_item and counter not in [
                        k.split("_")[0]
                        for k in expression_values.keys()
                        if k.startswith("val_")
                    ]:
                        # Only initialize if not already being updated
                        if not any(counter in part for part in add_parts + set_parts):
                            set_parts.append(f"{counter} = :init_{counter}")
                            expression_values[f":init_{counter}"] = 0

            # Always update timestamp
            set_parts.append("lastUpdated = :now")
            expression_values[":now"] = datetime.utcnow().isoformat()

            # Build the complete update expression
            update_expression_parts = []
            if add_parts:
                update_expression_parts.append("ADD " + ", ".join(add_parts))
            if set_parts:
                update_expression_parts.append("SET " + ", ".join(set_parts))

            if not update_expression_parts:
                logging.debug(f"No updates to apply for account {account_id}")
                continue

            update_expression = " ".join(update_expression_parts)

            # Perform the atomic update
            try:
                counts_table.update_item(
                    Key={"accountId": account_id},
                    UpdateExpression=update_expression,
                    ExpressionAttributeValues=expression_values,
                )
                updated_count += 1

            except ClientError as e:
                logging.error(
                    f"Error in atomic update for account {account_id}: {str(e)}"
                )
                raise

        except Exception as e:
            logging.error(f"Error updating live counts for {account_id}: {str(e)}")
            logging.error(f"{traceback.format_exc()}")
            failed_count += 1

    logging.info(
        f"Live counts update complete: {updated_count} updated, {failed_count} failed"
    )
    return {"updated": updated_count, "failed": failed_count}


def process_dynamodb_stream_records(stream_records):
    """
    Process DynamoDB Stream records for:
    1. TTL deletions - decrement counts for deleted events
    2. Status changes - update counts when event status changes (INSERT/MODIFY)

    Args:
        stream_records (list): List of DynamoDB stream records

    Returns:
        dict: Summary of processing results
    """
    if not COUNTS_TABLE_NAME:
        logging.warning("Counts table name not provided, skipping stream processing")
        return {"processed": 0, "count_updates": 0, "arns_updated": 0}

    logging.info(f"Processing {len(stream_records)} DynamoDB stream records")

    processed_count = 0
    ttl_deletions = []
    arns_to_update = set()  # Track unique ARNs that need count updates

    # Process each stream record
    for record in stream_records:
        try:
            event_name = record.get("eventName")
            dynamodb_data = record.get("dynamodb", {})

            # Handle REMOVE events (TTL deletions)
            if event_name == "REMOVE":
                # Check if this is a TTL deletion (vs user deletion)
                user_identity = record.get("userIdentity", {})
                if user_identity.get("principalId") != "dynamodb.amazonaws.com":
                    continue

                # Extract the deleted event data from OldImage
                old_image = dynamodb_data.get("OldImage", {})
                if not old_image:
                    continue

                # Convert DynamoDB format to regular dict
                deleted_event = {
                    "accountId": old_image.get("accountId", {}).get("S", "N/A"),
                    "service": old_image.get("service", {}).get("S", "N/A"),
                    "event_type_category": old_image.get("eventTypeCategory", {}).get(
                        "S", "N/A"
                    ),
                    "status_code": old_image.get("statusCode", {}).get("S", "unknown"),
                    "eventArn": old_image.get("eventArn", {}).get("S", "N/A"),
                }

                # Only process if we have valid data
                if (
                    deleted_event["accountId"] != "N/A"
                    and deleted_event["eventArn"] != "N/A"
                ):
                    ttl_deletions.append(deleted_event)
                    processed_count += 1

            # Handle INSERT and MODIFY events (status changes)
            elif event_name in ["INSERT", "MODIFY"]:
                old_image = dynamodb_data.get("OldImage", {})
                new_image = dynamodb_data.get("NewImage", {})

                if not new_image:
                    continue

                # Extract event ARN and status from new image
                event_arn = new_image.get("eventArn", {}).get("S", "")
                new_status = new_image.get("statusCode", {}).get("S", "")
                
                if not event_arn:
                    continue

                # For INSERT events, always update counts (new event)
                if event_name == "INSERT":
                    logging.debug(f"INSERT detected for ARN {event_arn}, status={new_status}")
                    arns_to_update.add(event_arn)
                    processed_count += 1
                
                # For MODIFY events, check if status changed
                elif event_name == "MODIFY" and old_image:
                    old_status = old_image.get("statusCode", {}).get("S", "")
                    
                    # Only update counts if status actually changed
                    if old_status != new_status:
                        logging.info(
                            f"Status change detected for ARN {event_arn}: "
                            f"{old_status} -> {new_status}"
                        )
                        arns_to_update.add(event_arn)
                        processed_count += 1
                    else:
                        logging.debug(f"MODIFY event for ARN {event_arn} but no status change")

        except Exception as e:
            logging.error(f"Error processing stream record: {str(e)}")
            logging.error(f"{traceback.format_exc()}")
            continue

    # Update counts for TTL deletions
    count_updates = 0
    if ttl_deletions:
        logging.info(f"Processing {len(ttl_deletions)} TTL deletions for count updates")

        # Convert to format expected by update_live_counts with negative changes
        events_for_count_update = []
        for deleted_event in ttl_deletions:
            # Only decrement counts if the event was contributing to live counts
            status = deleted_event["status_code"]
            if status in ["open", "upcoming", "scheduled"]:
                # Create event data for count decrement
                count_event = {
                    "accountId": deleted_event["accountId"],
                    "service": deleted_event["service"],
                    "event_type_category": deleted_event["event_type_category"],
                    "status_code": "closed",  # Treat as closed to trigger decrement
                    "eventArn": deleted_event["eventArn"],
                    "previous_status": status,  # Track what it was before deletion
                    "ttl_deletion": True,  # Flag to indicate this is TTL cleanup
                }
                events_for_count_update.append(count_event)

        if events_for_count_update:
            # Use existing update_live_counts function with special handling for TTL
            result = update_live_counts_for_ttl_deletions(events_for_count_update)
            count_updates = result.get("updated", 0)

    # Update counts for status changes (INSERT/MODIFY)
    arns_updated = 0
    if arns_to_update:
        logging.info(f"Updating counts for {len(arns_to_update)} ARNs with status changes")
        
        for event_arn in arns_to_update:
            try:
                # Use the efficient per-ARN update function
                result = update_counts_for_arn(event_arn)
                
                if "error" not in result:
                    arns_updated += result.get("updated", 0)
                    logging.debug(
                        f"Updated counts for ARN {event_arn}: "
                        f"{result.get('updated', 0)} accounts affected"
                    )
                else:
                    logging.error(f"Error updating counts for ARN {event_arn}: {result['error']}")
                    
            except Exception as e:
                logging.error(f"Error updating counts for ARN {event_arn}: {str(e)}")
                logging.error(f"{traceback.format_exc()}")
                continue

    logging.info(
        f"Stream processing complete: {processed_count} records processed, "
        f"{count_updates} TTL count updates, {arns_updated} accounts updated from status changes"
    )
    return {
        "processed": processed_count,
        "count_updates": count_updates,
        "arns_updated": arns_updated,
        "unique_arns_processed": len(arns_to_update)
    }


def update_live_counts_for_ttl_deletions(ttl_deletion_events):
    """
    Update live counts for TTL deletions - specialized version of update_live_counts

    Args:
        ttl_deletion_events (list): List of events deleted by TTL

    Returns:
        dict: Summary of count updates
    """
    if not COUNTS_TABLE_NAME:
        return {"updated": 0, "failed": 0}

    logging.info(f"Updating counts for {len(ttl_deletion_events)} TTL deletions")

    # Create DynamoDB resource
    dynamodb = boto3.resource("dynamodb")
    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)

    # Track updates by account
    account_updates = {}

    # Process each TTL deletion
    for event in ttl_deletion_events:
        account_id = event.get("accountId", "N/A")
        service = event.get("service", "").upper()
        event_type_category = event.get("event_type_category", "")
        previous_status = event.get("previous_status", "")

        # Skip events without valid account ID
        if account_id == "N/A" or not account_id:
            continue

        # Initialize account counters if needed
        if account_id not in account_updates:
            account_updates[account_id] = {
                "notifications": 0,
                "active_issues": 0,
                "scheduled": 0,
                "billing_changes": 0,
            }

        # Determine counter category
        counter_category = None
        if service == "BILLING":
            counter_category = "billing_changes"
        elif event_type_category == "accountNotification":
            counter_category = "notifications"
        elif event_type_category == "issue" and service != "BILLING":
            counter_category = "active_issues"
        elif event_type_category == "scheduledChange":
            counter_category = "scheduled"

        # Decrement count (TTL deletion means the event was contributing to counts)
        if counter_category and previous_status in ["open", "upcoming", "scheduled"]:
            account_updates[account_id][counter_category] -= 1

    # Apply updates to DynamoDB
    updated_count = 0
    failed_count = 0

    for account_id, updates in account_updates.items():
        try:
            # Only update if there are actual changes
            if any(value != 0 for value in updates.values()):
                # Get current values to ensure we don't go negative
                try:
                    current_response = counts_table.get_item(
                        Key={"accountId": account_id}
                    )
                    current_item = current_response.get("Item", {})

                    # Build SET expression to prevent negative values
                    set_parts = []
                    expression_values = {}

                    for counter, change_value in updates.items():
                        if change_value != 0:
                            current_value = current_item.get(counter, 0)
                            new_value = max(
                                0, current_value + change_value
                            )  # Prevent negative
                            set_parts.append(f"{counter} = :val_{counter}")
                            expression_values[f":val_{counter}"] = new_value

                    # Add timestamp
                    set_parts.append("lastUpdated = :now")
                    expression_values[":now"] = datetime.utcnow().isoformat()

                    if set_parts:
                        update_expression = "SET " + ", ".join(set_parts)
                        counts_table.update_item(
                            Key={"accountId": account_id},
                            UpdateExpression=update_expression,
                            ExpressionAttributeValues=expression_values,
                        )
                        updated_count += 1

                except Exception as e:
                    logging.error(f"Error updating counts for TTL deletion: {str(e)}")
                    failed_count += 1

        except Exception as e:
            logging.error(
                f"Error processing TTL deletion counts for {account_id}: {str(e)}"
            )
            failed_count += 1

    logging.info(
        f"TTL deletion count updates complete: {updated_count} updated, {failed_count} failed"
    )
    return {"updated": updated_count, "failed": failed_count}


def initialize_live_counts():
    """
    Initialize live counts based on current open events
    """
    if not DYNAMODB_TABLE_NAME:
        logging.error("Events table name not provided, cannot initialize counts")
        return

    logging.info("=== INITIALIZING LIVE COUNTS ===")

    # Query your events table for all open events
    dynamodb = boto3.resource("dynamodb")
    events_table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    # Scan for open events
    open_events = []
    try:
        logging.info("Scanning events table for open events...")
        response = events_table.scan(
            FilterExpression="statusCode = :open",
            ExpressionAttributeValues={":open": "open"},
        )

        open_events.extend(response.get("Items", []))

        # Handle pagination
        while "LastEvaluatedKey" in response:
            response = events_table.scan(
                FilterExpression="statusCode = :open",
                ExpressionAttributeValues={":open": "open"},
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )

            open_events.extend(response.get("Items", []))

    except Exception as e:
        logging.error(f"Error scanning for open events: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return

    logging.info(f"Total open events found: {len(open_events)}")

    # Convert to the format expected by update_live_counts
    events_analysis = []
    for event in open_events:
        events_analysis.append(
            {
                "accountId": event.get("accountId"),
                "service": event.get("service"),
                "event_type_category": event.get(
                    "eventTypeCategory"
                ),  # This field name matches what's stored in DynamoDB
                "status_code": "open",  # Force status to open for initialization
                "eventArn": event.get("eventArn"),
                "force_count": True,  # Flag to force counting during initialization
            }
        )

    # Update live counts
    if events_analysis:
        logging.info(
            f"Initializing live counts with {len(events_analysis)} open events"
        )
        result = update_live_counts(events_analysis)
        logging.info(f"Initialization result: {result}")
    else:
        logging.info("No open events found for initialization")


def ensure_all_counters_initialized():
    """
    Ensure all accounts have all counter categories initialized to 0
    This should be called periodically to maintain data consistency
    """
    if not COUNTS_TABLE_NAME:
        logging.error("Counts table name not provided, cannot initialize counters")
        return

    logging.info("=== ENSURING ALL COUNTERS ARE INITIALIZED ===")

    dynamodb = boto3.resource("dynamodb")
    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)

    required_counters = [
        "notifications",
        "active_issues",
        "scheduled",
        "billing_changes",
    ]

    try:
        # Scan all records in counts table
        response = counts_table.scan()
        items = response.get("Items", [])

        # Handle pagination
        while "LastEvaluatedKey" in response:
            response = counts_table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
            items.extend(response.get("Items", []))

        logging.info(f"Found {len(items)} account records in counts table")

        # Check each account record for missing counters
        for item in items:
            account_id = item.get("accountId")
            if not account_id:
                continue

            missing_counters = []
            for counter in required_counters:
                if counter not in item:
                    missing_counters.append(counter)

            if missing_counters:

                # Initialize missing counters to 0
                set_parts = []
                expression_values = {}

                for counter in missing_counters:
                    set_parts.append(f"{counter} = :init_{counter}")
                    expression_values[f":init_{counter}"] = 0

                # Add timestamp
                set_parts.append("lastUpdated = :now")
                expression_values[":now"] = datetime.utcnow().isoformat()

                update_expression = "SET " + ", ".join(set_parts)

                try:
                    counts_table.update_item(
                        Key={"accountId": account_id},
                        UpdateExpression=update_expression,
                        ExpressionAttributeValues=expression_values,
                    )
                    logging.info(
                        f"Initialized missing counters for account {account_id}: {missing_counters}"
                    )
                except Exception as e:
                    logging.error(
                        f"Error initializing counters for account {account_id}: {str(e)}"
                    )
            else:
                logging.debug(f"Account {account_id} has all required counters")

    except Exception as e:
        logging.error(f"Error ensuring counters are initialized: {str(e)}")
        logging.error(f"{traceback.format_exc()}")


def force_counts_update():
    """
    Force update counts based on all events in the events table (for debugging)
    """
    if not DYNAMODB_TABLE_NAME:
        logging.error("Events table name not provided, cannot force counts update")
        return

    logging.info("=== FORCING COUNTS UPDATE ===")

    # Query your events table for all events
    dynamodb = boto3.resource("dynamodb")
    events_table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    # Scan for all events
    all_events = []
    try:
        logging.info("Scanning events table for all events...")
        response = events_table.scan()

        all_events.extend(response.get("Items", []))

        # Handle pagination
        while "LastEvaluatedKey" in response:
            response = events_table.scan(
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )

            all_events.extend(response.get("Items", []))

    except Exception as e:
        logging.error(f"Error scanning for all events: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return

    # Convert to the format expected by update_live_counts
    events_analysis = []
    for event in all_events:
        status = event.get("statusCode", "unknown")
        logging.debug(
            f"Event: ARN={event.get('eventArn')}, Account={event.get('accountId')}, Category={event.get('eventTypeCategory')}, Service={event.get('service')}, Status={status}"
        )

        events_analysis.append(
            {
                "accountId": event.get("accountId"),
                "service": event.get("service"),
                "event_type_category": event.get("eventTypeCategory"),
                "status_code": status,
                "eventArn": event.get("eventArn"),
            }
        )

    # Update live counts
    if events_analysis:
        logging.info(f"Force updating live counts with {len(events_analysis)} events")
        result = update_live_counts(events_analysis)
        logging.info(f"Force update result: {result}")
    else:
        logging.info("No events found for force update")


def update_counts_for_arn(event_arn, affected_account_ids=None):
    """
    Update counts for a specific ARN using ARN-based logic.
    
    This is an efficient incremental update that only queries the specific ARN,
    not the entire events table.
    
    Counts table logic:
    - Count each unique health event ARN only ONCE per account
    - An ARN is considered "closed" only if ALL accounts under that ARN have status "closed"
    - If ANY account under an ARN has status != "closed", the ARN counts as open/active
    
    Args:
        event_arn (str): The event ARN to update counts for
        affected_account_ids (list): Optional list of account IDs to update (optimization)
    
    Returns:
        dict: Summary of the update
    """
    if not DYNAMODB_TABLE_NAME or not COUNTS_TABLE_NAME or not event_arn:
        logging.warning("Missing configuration for ARN-based count update")
        return {"updated": 0}

    dynamodb = boto3.resource("dynamodb")
    events_table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)

    try:
        # Query all records for this specific ARN (efficient - uses partition key)
        response = events_table.query(
            KeyConditionExpression="eventArn = :arn",
            ExpressionAttributeValues={":arn": event_arn},
            ProjectionExpression="eventArn, accountId, statusCode, eventTypeCategory, service"
        )
        arn_records = response.get("Items", [])
        
        # Handle pagination (unlikely for single ARN but be safe)
        while "LastEvaluatedKey" in response:
            response = events_table.query(
                KeyConditionExpression="eventArn = :arn",
                ExpressionAttributeValues={":arn": event_arn},
                ProjectionExpression="eventArn, accountId, statusCode, eventTypeCategory, service",
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            arn_records.extend(response.get("Items", []))

        if not arn_records:
            logging.debug(f"No records found for ARN: {event_arn}")
            return {"updated": 0}

        # Determine if ARN is effectively closed (ALL accounts closed)
        all_closed = all(r.get("statusCode") == "closed" for r in arn_records)
        
        # Get category info from first record
        category = arn_records[0].get("eventTypeCategory", "")
        service = (arn_records[0].get("service", "") or "").upper()
        
        # Determine counter category
        counter_category = None
        if service == "BILLING":
            counter_category = "billing_changes"
        elif category == "accountNotification":
            counter_category = "notifications"
        elif category == "issue" and service != "BILLING":
            counter_category = "active_issues"
        elif category == "scheduledChange":
            counter_category = "scheduled"
        
        if not counter_category:
            logging.debug(f"ARN {event_arn} doesn't map to a counter category")
            return {"updated": 0}

        # Get affected accounts from records
        accounts_in_arn = set(r.get("accountId") for r in arn_records if r.get("accountId"))
        
        # For each affected account, we need to recalculate their count for this category
        # This requires checking ALL ARNs for that account in that category
        updated_count = 0
        
        for account_id in accounts_in_arn:
            try:
                # Query all ARNs for this account to count unique open ARNs
                # Use a GSI if available, otherwise scan with filter
                # For now, we'll do a targeted scan for this account's events
                account_events = []
                scan_response = events_table.scan(
                    FilterExpression="accountId = :aid",
                    ExpressionAttributeValues={":aid": account_id},
                    ProjectionExpression="eventArn, statusCode, eventTypeCategory, service"
                )
                account_events.extend(scan_response.get("Items", []))
                
                while "LastEvaluatedKey" in scan_response:
                    scan_response = events_table.scan(
                        FilterExpression="accountId = :aid",
                        ExpressionAttributeValues={":aid": account_id},
                        ProjectionExpression="eventArn, statusCode, eventTypeCategory, service",
                        ExclusiveStartKey=scan_response["LastEvaluatedKey"]
                    )
                    account_events.extend(scan_response.get("Items", []))
                
                # Group by ARN and check if each ARN is fully closed
                from collections import defaultdict
                arn_statuses = defaultdict(list)
                arn_categories = {}
                
                for evt in account_events:
                    arn = evt.get("eventArn", "")
                    if arn:
                        arn_statuses[arn].append(evt.get("statusCode", "unknown"))
                        evt_category = evt.get("eventTypeCategory", "")
                        evt_service = (evt.get("service", "") or "").upper()
                        
                        # Determine category for this ARN
                        if evt_service == "BILLING":
                            arn_categories[arn] = "billing_changes"
                        elif evt_category == "accountNotification":
                            arn_categories[arn] = "notifications"
                        elif evt_category == "issue" and evt_service != "BILLING":
                            arn_categories[arn] = "active_issues"
                        elif evt_category == "scheduledChange":
                            arn_categories[arn] = "scheduled"
                
                # Now we need to check if each ARN is fully closed across ALL accounts
                # This is the tricky part - we need to query each ARN
                category_counts = {
                    "notifications": 0,
                    "active_issues": 0,
                    "scheduled": 0,
                    "billing_changes": 0,
                }
                
                for arn, cat in arn_categories.items():
                    if not cat:
                        continue
                    
                    # Check if this ARN is fully closed (all accounts)
                    arn_response = events_table.query(
                        KeyConditionExpression="eventArn = :arn",
                        ExpressionAttributeValues={":arn": arn},
                        ProjectionExpression="statusCode"
                    )
                    all_statuses = [r.get("statusCode") for r in arn_response.get("Items", [])]
                    
                    # ARN is open if ANY account is not closed
                    if not all(s == "closed" for s in all_statuses):
                        category_counts[cat] += 1
                
                # Update counts table for this account
                counts_table.update_item(
                    Key={"accountId": account_id},
                    UpdateExpression="SET notifications = :n, active_issues = :a, scheduled = :s, billing_changes = :b, lastUpdated = :now",
                    ExpressionAttributeValues={
                        ":n": category_counts["notifications"],
                        ":a": category_counts["active_issues"],
                        ":s": category_counts["scheduled"],
                        ":b": category_counts["billing_changes"],
                        ":now": datetime.utcnow().isoformat(),
                    },
                )
                updated_count += 1
                logging.debug(f"Updated counts for account {account_id}: {category_counts}")
                
            except Exception as e:
                logging.error(f"Error updating counts for account {account_id}: {str(e)}")
        
        return {"updated": updated_count, "arn": event_arn, "all_closed": all_closed}
        
    except Exception as e:
        logging.error(f"Error in update_counts_for_arn: {str(e)}")
        return {"error": str(e)}


def recalculate_arn_based_counts():
    """
    Full recalculation of counts based on unique ARNs across all accounts.
    
    USE SPARINGLY - this does a full table scan. Prefer update_counts_for_arn()
    for incremental updates during normal event processing.
    
    Counts table logic:
    - Count each unique health event ARN only ONCE
    - An ARN is considered "closed" only if ALL accounts under that ARN have status "closed"
    - If ANY account under an ARN has status != "closed", the ARN counts as open/active
    
    Returns:
        dict: Summary of the recalculation with counts by category
    """
    if not DYNAMODB_TABLE_NAME or not COUNTS_TABLE_NAME:
        logging.error("Table names not provided, cannot recalculate ARN-based counts")
        return {"error": "Missing table configuration"}

    logging.info("=== RECALCULATING ARN-BASED COUNTS (FULL SCAN) ===")

    dynamodb = boto3.resource("dynamodb")
    events_table = dynamodb.Table(DYNAMODB_TABLE_NAME)
    counts_table = dynamodb.Table(COUNTS_TABLE_NAME)

    # Step 1: Scan all events and group by ARN
    all_events = []
    try:
        logging.info("Scanning events table...")
        response = events_table.scan(
            ProjectionExpression="eventArn, accountId, statusCode, eventTypeCategory, service"
        )
        all_events.extend(response.get("Items", []))

        while "LastEvaluatedKey" in response:
            response = events_table.scan(
                ProjectionExpression="eventArn, accountId, statusCode, eventTypeCategory, service",
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )
            all_events.extend(response.get("Items", []))

        logging.info(f"Found {len(all_events)} total event+account records")

    except Exception as e:
        logging.error(f"Error scanning events table: {str(e)}")
        return {"error": str(e)}

    # Step 2: Group events by ARN and determine effective status
    from collections import defaultdict
    
    arn_data = defaultdict(lambda: {"accounts": [], "category": None, "service": None})
    
    for event in all_events:
        arn = event.get("eventArn", "")
        if not arn:
            continue
            
        account_id = event.get("accountId", "")
        status = event.get("statusCode", "unknown")
        category = event.get("eventTypeCategory", "")
        service = (event.get("service", "") or "").upper()
        
        arn_data[arn]["accounts"].append({"accountId": account_id, "status": status})
        arn_data[arn]["category"] = category
        arn_data[arn]["service"] = service

    logging.info(f"Found {len(arn_data)} unique ARNs")

    # Step 3: Count open ARNs per account per category
    account_arn_counts = defaultdict(lambda: {
        "notifications": set(),
        "active_issues": set(),
        "scheduled": set(),
        "billing_changes": set(),
    })
    
    for arn, data in arn_data.items():
        accounts = data["accounts"]
        category = data["category"]
        service = data["service"]
        
        # ARN is closed only if ALL accounts are closed
        all_closed = all(a["status"] == "closed" for a in accounts)
        
        if all_closed:
            continue
        
        # Determine counter category
        counter_category = None
        if service == "BILLING":
            counter_category = "billing_changes"
        elif category == "accountNotification":
            counter_category = "notifications"
        elif category == "issue" and service != "BILLING":
            counter_category = "active_issues"
        elif category == "scheduledChange":
            counter_category = "scheduled"
        
        if not counter_category:
            continue
        
        # Add this ARN to each account that has it
        for account_info in accounts:
            account_id = account_info["accountId"]
            if account_id:
                account_arn_counts[account_id][counter_category].add(arn)

    # Step 4: Get existing accounts and update
    existing_accounts = set()
    try:
        response = counts_table.scan(ProjectionExpression="accountId")
        for item in response.get("Items", []):
            existing_accounts.add(item.get("accountId", ""))
        while "LastEvaluatedKey" in response:
            response = counts_table.scan(
                ProjectionExpression="accountId",
                ExclusiveStartKey=response["LastEvaluatedKey"]
            )
            for item in response.get("Items", []):
                existing_accounts.add(item.get("accountId", ""))
    except Exception as e:
        logging.error(f"Error scanning counts table: {str(e)}")

    all_accounts = existing_accounts.union(set(account_arn_counts.keys()))
    updated_count = 0
    
    for account_id in all_accounts:
        if not account_id:
            continue
            
        try:
            counts = account_arn_counts.get(account_id, {
                "notifications": set(),
                "active_issues": set(),
                "scheduled": set(),
                "billing_changes": set(),
            })
            
            counts_table.update_item(
                Key={"accountId": account_id},
                UpdateExpression="SET notifications = :n, active_issues = :a, scheduled = :s, billing_changes = :b, lastUpdated = :now",
                ExpressionAttributeValues={
                    ":n": len(counts["notifications"]),
                    ":a": len(counts["active_issues"]),
                    ":s": len(counts["scheduled"]),
                    ":b": len(counts["billing_changes"]),
                    ":now": datetime.utcnow().isoformat(),
                },
            )
            updated_count += 1
            
        except Exception as e:
            logging.error(f"Error updating counts for account {account_id}: {str(e)}")

    total_open_arns = len([arn for arn, data in arn_data.items() 
                          if not all(a["status"] == "closed" for a in data["accounts"])])
    
    summary = {
        "total_unique_arns": len(arn_data),
        "open_arns": total_open_arns,
        "closed_arns": len(arn_data) - total_open_arns,
        "accounts_updated": updated_count,
    }
    
    logging.info(f"ARN-based counts recalculation complete: {summary}")
    return summary
