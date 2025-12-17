"""
DynamoDB Stream processing for TTL deletions and count updates
"""

import json
import logging
import traceback
from storage.dynamodb_handler import process_dynamodb_stream_records


def process_dynamodb_stream_event(event, context):
    """
    Process DynamoDB Stream event for TTL deletions and update counts

    Args:
        event (dict): Lambda event from DynamoDB Streams
        context: Lambda context

    Returns:
        dict: Processing result
    """
    try:
        logging.info(
            f"Processing DynamoDB Stream event with {len(event['Records'])} records"
        )

        # Process the stream records
        result = process_dynamodb_stream_records(event["Records"])

        logging.info(f"Stream processing complete: {result}")

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "DynamoDB Stream processed successfully",
                    "records_processed": result.get("processed", 0),
                    "ttl_count_updates": result.get("count_updates", 0),
                    "accounts_updated_from_status_changes": result.get("arns_updated", 0),
                    "unique_arns_processed": result.get("unique_arns_processed", 0),
                }
            ),
        }

    except Exception as e:
        logging.error(f"Error processing DynamoDB Stream event: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return {
            "statusCode": 500,
            "body": json.dumps(
                {"error": f"Failed to process DynamoDB Stream: {str(e)}"}
            ),
        }
