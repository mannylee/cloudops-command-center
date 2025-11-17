"""
SQS event processing for individual health events
"""

import json
import logging
import traceback
import re
from aws_clients.client_manager import get_clients
from utils.event_helpers import normalize_event_format
from storage.dynamodb_handler import (
    process_single_event,
    store_events_in_dynamodb,
    update_live_counts,
    ensure_all_counters_initialized,
)


def process_sqs_event(event, context):
    """
    Process individual event from SQS queue

    Args:
        event (dict): Lambda event from SQS
        context: Lambda context

    Returns:
        dict: Processing result with batch item failures format
    """
    try:
        # Initialize clients
        health_client, bedrock_client, sqs_client = get_clients()

        # Extract the health event data from SQS message
        sqs_record = event["Records"][0]
        raw_body = sqs_record["body"]

        # Handle JSON parsing with potential escape sequence issues
        try:
            message_body = json.loads(raw_body)
        except json.JSONDecodeError as e:
            logging.error(f"JSON decode error: {str(e)}")
            # Try to fix invalid escape sequences
            try:
                # Replace invalid escape sequences with spaces or remove them
                fixed_body = re.sub(
                    r"\\x[0-9a-fA-F]{2}", " ", raw_body
                )  # Replace hex escapes
                fixed_body = re.sub(
                    r'\\[^"\\bfnrt/]', " ", fixed_body
                )  # Replace other invalid escapes
                message_body = json.loads(fixed_body)
                logging.info(
                    "Successfully parsed JSON after fixing escape sequences"
                )
            except json.JSONDecodeError as e2:
                logging.error(
                    f"Failed to parse JSON even after fixing: {str(e2)}"
                )
                return {
                    "batchItemFailures": [
                        {"itemIdentifier": sqs_record.get("messageId")}
                    ]
                }

        # Add debugging for problematic messages
        logging.debug(
            f"Processing message with keys: {list(message_body.keys())}"
        )
        if "detail" in message_body:
            detail = message_body["detail"]
            logging.debug(f"Detail keys: {list(detail.keys())}")
            if "eventDescription" in detail:
                event_desc = detail["eventDescription"]
                logging.debug(f"EventDescription type: {type(event_desc)}")
                if isinstance(event_desc, list):
                    logging.debug(
                        f"EventDescription list length: {len(event_desc)}"
                    )
                    if len(event_desc) > 0:
                        logging.debug(f"First item type: {type(event_desc[0])}")

        # Normalize event format (handles both EventBridge and API formats)
        try:
            health_event = normalize_event_format(message_body)
        except Exception as e:
            logging.error(f"Error normalizing event format: {str(e)}")
            logging.debug(
                f"Message body: {json.dumps(message_body, default=str)}"
            )
            # Return failure for this specific message
            return {
                "batchItemFailures": [{"itemIdentifier": sqs_record.get("messageId")}]
            }

        # Process the individual event
        events_analysis = process_single_event(bedrock_client, health_event)

        if events_analysis:
            # Update live counts BEFORE storing (so we can check previous status)
            counts_result = update_live_counts(events_analysis, is_sqs_processing=True)

            # Store in DynamoDB AFTER counting
            storage_result = store_events_in_dynamodb(events_analysis)

            logging.info(
                f"Successfully processed individual event: stored={storage_result.get('stored', 0)}, updated={storage_result.get('updated', 0)}, counts_updated={counts_result.get('updated', 0)}"
            )

            # Ensure all counter categories are initialized for all accounts
            try:
                ensure_all_counters_initialized()
            except Exception as e:
                logging.error(f"Error ensuring counters initialized: {str(e)}")

            return {"batchItemFailures": []}  # No failures
        else:
            logging.error("Failed to process individual event")
            return {
                "batchItemFailures": [{"itemIdentifier": sqs_record.get("messageId")}]
            }

    except Exception as e:
        logging.error(f"Error processing SQS event: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return {
            "batchItemFailures": [
                {"itemIdentifier": event["Records"][0].get("messageId")}
            ]
        }


# SQS sending functionality moved to utils/sqs_helpers.py to avoid circular imports
