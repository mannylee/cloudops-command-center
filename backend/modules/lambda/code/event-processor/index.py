"""
Main Lambda handler for AWS Health Event Processor
Routes events to appropriate processors based on event source
"""

import os
import json
import logging
import traceback

from utils.event_helpers import is_sqs_event, is_dynamodb_stream_event
from processing.sqs_processor import process_sqs_event
from processing.stream_processor import process_dynamodb_stream_event
from processing.batch_processor import process_single_event_mode, process_batch_events
from aws_clients.client_manager import get_clients

# Set up logging for Lambda
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# Environment variables
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_HEALTH_EVENTS_TABLE_NAME")


def handler(event, context):
    """
    Main Lambda handler - routes events to appropriate processors

    Args:
        event (dict): Lambda event
        context: Lambda context

    Returns:
        dict: Processing result
    """
    logger.info(
        f"Event processor handler invoked with event: {json.dumps(event, default=str)}"
    )
    logger.info("Starting execution...")
    logger.debug(f"Raw event: {event}")

    try:
        # Route based on event source
        if is_dynamodb_stream_event(event):
            logger.info("Detected DynamoDB Stream event")
            logger.debug(
                f"Stream event contains {len(event.get('Records', []))} records"
            )
            return process_dynamodb_stream_event(event, context)

        elif is_sqs_event(event):
            logger.info("Detected SQS event")
            logger.debug(f"SQS event contains {len(event.get('Records', []))} records")
            return process_sqs_event(event, context)

        else:
            # Batch processing, scheduled sync, or single event mode
            logger.info("Detected batch/single event/scheduled sync processing")

            # Initialize clients
            logger.debug("Initializing AWS clients")
            health_client, bedrock_client, sqs_client = get_clients()

            # Check if we're in recalculate_counts mode (ARN-based counting)
            if isinstance(event, dict) and event.get("mode") == "recalculate_counts":
                logger.info("Recalculate ARN-based counts mode triggered")
                from storage.dynamodb_handler import recalculate_arn_based_counts
                result = recalculate_arn_based_counts()
                return {
                    "statusCode": 200,
                    "body": json.dumps(result, default=str)
                }
            # Check if we're in scheduled sync mode
            elif isinstance(event, dict) and event.get("mode") == "scheduled_sync":
                logger.info("Scheduled sync mode triggered")
                lookback_days = event.get("lookback_days", 30)
                logger.info(f"Syncing events from last {lookback_days} days")
                return process_batch_events(
                    health_client, bedrock_client, sqs_client, context,
                    lookback_days=lookback_days
                )
            # Check if we're in single event processing mode
            elif isinstance(event, dict) and "event_arn" in event and DYNAMODB_TABLE_NAME:
                logger.info(
                    f"Single event processing mode for ARN: {event.get('event_arn')}"
                )
                return process_single_event_mode(event, health_client, bedrock_client)
            else:
                logger.info("Batch processing mode")
                logger.debug(f"DynamoDB table configured: {bool(DYNAMODB_TABLE_NAME)}")
                return process_batch_events(
                    health_client, bedrock_client, sqs_client, context
                )

    except Exception as e:
        logger.error(f"Error in main handler: {str(e)}")
        logger.error("Full traceback:", exc_info=True)
        return {"statusCode": 500, "body": f"Error: {str(e)}"}
