"""
Event helper functions for detecting and normalizing different event types
"""

import json
import logging
from datetime import datetime


def extract_event_description(event_description):
    """
    Safely extract description from various eventDescription formats

    Args:
        event_description: Can be dict, list, string, or None

    Returns:
        str: Extracted description or empty string
    """
    try:
        if not event_description:
            return ""

        # Case 1: Dictionary with latestDescription
        if isinstance(event_description, dict):
            return event_description.get("latestDescription", "")

        # Case 2: List of description objects
        elif isinstance(event_description, list):
            if len(event_description) > 0:
                first_desc = event_description[0]
                if isinstance(first_desc, dict):
                    return first_desc.get("latestDescription", "")
                elif isinstance(first_desc, str):
                    return first_desc
            return ""

        # Case 3: Direct string
        elif isinstance(event_description, str):
            return event_description

        # Case 4: Unknown format
        else:
            return str(event_description) if event_description else ""

    except Exception as e:
        logging.error(f"Error extracting event description: {str(e)}")
        return ""


def is_sqs_event(event):
    """
    Check if the event is from SQS (individual processing mode)

    Args:
        event (dict): Lambda event

    Returns:
        bool: True if event is from SQS
    """
    return (
        "Records" in event
        and len(event["Records"]) > 0
        and event["Records"][0].get("eventSource") == "aws:sqs"
    )


def is_dynamodb_stream_event(event):
    """
    Check if the event is from DynamoDB Streams (TTL deletions)

    Args:
        event (dict): Lambda event

    Returns:
        bool: True if event is from DynamoDB Streams
    """
    return (
        "Records" in event
        and len(event["Records"]) > 0
        and event["Records"][0].get("eventSource") == "aws:dynamodb"
    )


def normalize_event_format(message_body):
    """
    Convert EventBridge format to API format for consistent processing

    Args:
        message_body (dict): Raw message body from SQS

    Returns:
        dict: Normalized event in API format
    """
    # Check if this is an EventBridge event
    if "detail-type" in message_body and message_body.get("source") == "aws.health":
        detail = message_body["detail"]

        # Convert EventBridge format to API format
        account_id = detail.get("accountId", "N/A")
        if account_id == "N/A":
            account_id = detail.get("affectedAccount", "N/A")

        # Handle region - use "global" for events without a specific region
        region = detail.get("region", "")
        if not region or region == "":
            region = "global"
        
        normalized_event = {
            "arn": detail.get("eventArn", ""),
            "eventArn": detail.get("eventArn", ""),
            "eventTypeCode": detail.get("eventTypeCode", ""),
            "eventTypeCategory": detail.get("eventTypeCategory", ""),
            "service": detail.get("service", ""),
            "region": region,
            "startTime": detail.get("startTime", ""),
            "lastUpdatedTime": detail.get("lastUpdatedTime", ""),
            "statusCode": detail.get("statusCode", ""),
            "accountId": account_id,
            "description": extract_event_description(
                detail.get("eventDescription", "")
            ),
        }

        return normalized_event
    else:
        return message_body


def expand_events_by_account(events):
    """
    Expands events that affect multiple accounts into separate event records for each account.

    Args:
        events (list): List of health events

    Returns:
        list: Expanded list with separate records for each affected account
    """
    expanded_events = []

    for event in events:
        # Get affected accounts for this event
        affected_accounts = event.get("affectedAccounts", [])

        if affected_accounts:
            # Create separate event record for each affected account
            for account_id in affected_accounts:
                account_event = event.copy()
                account_event["accountId"] = account_id
                expanded_events.append(account_event)
        else:
            # No affected accounts specified, keep original event
            expanded_events.append(event)

    logging.info(
        f"Expanded {len(events)} events to {len(expanded_events)} account-specific events"
    )
    return expanded_events
