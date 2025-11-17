"""
SQS utility functions
"""

import json
import os
import boto3
import logging


def send_events_to_sqs(events_data):
    """
    Send events to SQS queue for parallel processing

    Args:
        events_data (list): List of health events to process

    Returns:
        dict: Summary of SQS operations
    """
    sqs_queue_url = os.environ.get("SQS_EVENT_PROCESSING_QUEUE_URL")

    if not sqs_queue_url:
        logging.warning(
            "SQS_EVENT_PROCESSING_QUEUE_URL not configured, falling back to synchronous processing"
        )
        return {"sent": 0, "failed": 0, "fallback": True}

    sqs_client = boto3.client("sqs")
    sent_count = 0
    failed_count = 0

    for i, event_data in enumerate(events_data):
        try:
            # Send individual event to SQS
            message_body = json.dumps(event_data, default=str)

            sqs_client.send_message(QueueUrl=sqs_queue_url, MessageBody=message_body)

            sent_count += 1

        except Exception as e:
            logging.error(f"Error sending event {i+1} to SQS: {str(e)}")
            failed_count += 1

    logging.info(f"SQS batch complete: {sent_count} sent, {failed_count} failed")
    return {"sent": sent_count, "failed": failed_count, "fallback": False}
