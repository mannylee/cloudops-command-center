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
    Process event from SQS queue - supports both batch and single-event formats.
    
    New batch format (optimized):
    {
        "event": {...},
        "accounts": ["123...", "456..."],
        "analysis": "pre-computed analysis",
        "categories": {...},
        "batchNumber": 1,
        "totalBatches": 8
    }
    
    Old single-event format (backward compatible):
    {
        "arn": "...",
        "accountId": "...",
        ...
    }

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
        
        # Check if this is the new batch format or old single-event format
        if "accounts" in message_body and "analysis" in message_body and "categories" in message_body:
            # New optimized batch format
            logging.info("Processing message in new batch format (optimized)")
            return process_batch_message(message_body, health_client, sqs_record, context)
        else:
            # Old single-event format (backward compatibility)
            logging.info("Processing message in legacy single-event format")
            return process_legacy_single_event(message_body, bedrock_client, sqs_record)
            
    except Exception as e:
        logging.error(f"Error processing SQS event: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return {
            "batchItemFailures": [
                {"itemIdentifier": event["Records"][0].get("messageId")}
            ]
        }


def process_batch_message(message_body, health_client, sqs_record, context):
    """
    Process new batch message format with pre-computed analysis.
    
    Args:
        message_body: Parsed message body with batch data
        health_client: AWS Health client
        sqs_record: SQS record for error handling
        context: Lambda context
        
    Returns:
        dict: Processing result with batch item failures
    """
    try:
        # Extract batch data from message
        event_data = message_body.get("event", {})
        account_batch = message_body.get("accounts", [])
        analysis = message_body.get("analysis", "")
        categories = message_body.get("categories", {})
        batch_num = message_body.get("batchNumber", 1)
        total_batches = message_body.get("totalBatches", 1)
        
        # Validate required fields
        if not analysis:
            logging.error("Analysis payload missing from SQS message")
            return {
                "batchItemFailures": [
                    {"itemIdentifier": sqs_record.get("messageId")}
                ]
            }
        
        if not account_batch:
            logging.error("Accounts array missing or empty in SQS message")
            return {
                "batchItemFailures": [
                    {"itemIdentifier": sqs_record.get("messageId")}
                ]
            }
        
        logging.info(
            f"Processing batch {batch_num}/{total_batches} "
            f"with {len(account_batch)} accounts "
            f"(reusing pre-computed analysis)"
        )
        
        # Import here to avoid circular dependency
        from aws_clients.organizations_client import get_account_name
        from aws_clients.health_client import fetch_health_event_details_for_org
        from utils.helpers import format_time, extract_affected_resources
        
        # Process each account in the batch
        events_analysis = []
        successful_accounts = 0
        failed_accounts = 0
        
        for account_id in account_batch:
            try:
                # Fetch account-specific data
                account_name = get_account_name(account_id)
                
                # Fetch affected resources AND description for this account
                health_data = fetch_health_event_details_for_org(
                    event_data.get("arn", ""),
                    account_id
                )
                
                affected_resources = extract_affected_resources(
                    health_data.get("entities", [])
                )
                
                # Extract description from health data (same for all accounts, but fetched per account)
                description = (
                    health_data.get("details", {})
                    .get("eventDescription", {})
                    .get("latestDescription", "No description available")
                )
                if not description:
                    description = "No description available"
                
                # Handle region - use "global" for events without a specific region
                event_region = event_data.get("region", "")
                if not event_region or event_region == "":
                    event_region = "global"
                
                # Build event record with SHARED analysis and FETCHED description
                event_entry = {
                    "arn": event_data.get("arn", "N/A"),
                    "eventArn": event_data.get("eventArn", event_data.get("arn", "N/A")),
                    "event_type": event_data.get("eventTypeCode", "N/A"),
                    "service": event_data.get("service", "N/A"),
                    "description": description,  # FETCHED from Health API
                    "region": event_region,
                    "start_time": format_time(event_data.get("startTime", "N/A")),
                    "last_update_time": format_time(event_data.get("lastUpdatedTime", "N/A")),
                    "status_code": event_data.get("statusCode", "unknown"),
                    "event_type_category": event_data.get("eventTypeCategory", "N/A"),
                    "analysis_text": analysis,  # REUSED from message
                    "critical": categories.get("critical", False),  # REUSED
                    "risk_level": categories.get("risk_level", "LOW"),  # REUSED
                    "accountId": account_id,
                    "accountName": account_name,
                    "impact_analysis": categories.get("impact_analysis", ""),  # REUSED
                    "required_actions": categories.get("required_actions", ""),  # REUSED
                    "time_sensitivity": categories.get("time_sensitivity", "Routine"),  # REUSED
                    "risk_category": categories.get("risk_category", "Unknown"),  # REUSED
                    "consequences_if_ignored": categories.get("consequences_if_ignored", ""),  # REUSED
                    "affected_resources": affected_resources,  # ACCOUNT-SPECIFIC
                    "event_impact_type": categories.get("event_impact_type", "Unknown"),  # REUSED
                }
                
                events_analysis.append(event_entry)
                successful_accounts += 1
                
            except Exception as e:
                logging.error(f"Error processing account {account_id}: {str(e)}")
                logging.error(f"{traceback.format_exc()}")
                failed_accounts += 1
                # Continue processing remaining accounts
                continue
        
        # Store all successfully processed accounts in DynamoDB (batch write)
        if events_analysis:
            logging.info(f"Storing {len(events_analysis)} event records in DynamoDB (batch write)")
            
            # Update live counts BEFORE storing
            counts_result = update_live_counts(events_analysis, is_sqs_processing=True)
            
            # Batch write to DynamoDB
            storage_result = store_events_in_dynamodb(events_analysis)
            
            # Ensure all counter categories are initialized
            try:
                ensure_all_counters_initialized()
            except Exception as e:
                logging.error(f"Error ensuring counters initialized: {str(e)}")
            
            logging.info(
                f"Batch {batch_num}/{total_batches} complete: "
                f"successful={successful_accounts}, failed={failed_accounts}, "
                f"stored={storage_result.get('stored', 0)}, updated={storage_result.get('updated', 0)}"
            )
            
            return {"batchItemFailures": []}  # Success
        else:
            logging.error(f"No accounts successfully processed in batch {batch_num}/{total_batches}")
            return {
                "batchItemFailures": [
                    {"itemIdentifier": sqs_record.get("messageId")}
                ]
            }
            
    except Exception as e:
        logging.error(f"Error processing batch message: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return {
            "batchItemFailures": [
                {"itemIdentifier": sqs_record.get("messageId")}
            ]
        }


def process_legacy_single_event(message_body, bedrock_client, sqs_record):
    """
    Process legacy single-event message format (backward compatibility).
    
    Args:
        message_body: Parsed message body
        bedrock_client: Bedrock client for analysis
        sqs_record: SQS record for error handling
        
    Returns:
        dict: Processing result with batch item failures
    """
    try:

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

        # Process the individual event (with Bedrock analysis)
        events_analysis = process_single_event(bedrock_client, health_event)

        if events_analysis:
            # Update live counts BEFORE storing (so we can check previous status)
            counts_result = update_live_counts(events_analysis, is_sqs_processing=True)

            # Store in DynamoDB AFTER counting
            storage_result = store_events_in_dynamodb(events_analysis)

            logging.info(
                f"Successfully processed individual event (legacy format): stored={storage_result.get('stored', 0)}, updated={storage_result.get('updated', 0)}, counts_updated={counts_result.get('updated', 0)}"
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
        logging.error(f"Error processing legacy single event: {str(e)}")
        logging.error(f"{traceback.format_exc()}")
        return {
            "batchItemFailures": [
                {"itemIdentifier": sqs_record.get("messageId")}
            ]
        }


# SQS sending functionality moved to utils/sqs_helpers.py to avoid circular imports
