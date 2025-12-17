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
            return process_batch_message(message_body, health_client, bedrock_client, sqs_record, context)
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


def process_batch_message(message_body, health_client, bedrock_client, sqs_record, context):
    """
    Process new batch message format with pre-computed analysis.
    
    Args:
        message_body: Parsed message body with batch data
        health_client: AWS Health client
        bedrock_client: Bedrock client for analysis (when deferred)
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
        if not account_batch:
            logging.error("Accounts array missing or empty in SQS message")
            return {
                "batchItemFailures": [
                    {"itemIdentifier": sqs_record.get("messageId")}
                ]
            }
        
        # Check if we need to perform Bedrock analysis (deferred from main Lambda)
        needs_bedrock_analysis = (not analysis or not categories or 
                                   analysis is None or categories is None)
        
        if needs_bedrock_analysis:
            logging.info(
                f"Processing batch {batch_num}/{total_batches} "
                f"with {len(account_batch)} accounts "
                f"(will perform Bedrock analysis in SQS worker)"
            )
        else:
            logging.info(
                f"Processing batch {batch_num}/{total_batches} "
                f"with {len(account_batch)} accounts "
                f"(reusing pre-computed analysis)"
            )
        
        # Import here to avoid circular dependency
        from aws_clients.organizations_client import get_account_name
        from aws_clients.health_client import fetch_health_event_details_for_org, fetch_per_account_status_batch
        from utils.helpers import format_date_only, format_datetime, extract_affected_resources
        from analysis.bedrock_analyzer import analyze_event_with_bedrock, categorize_analysis
        
        # If analysis is missing, perform Bedrock analysis now (once for all accounts in batch)
        if needs_bedrock_analysis:
            logging.info(f"Performing Bedrock analysis for event {event_data.get('eventTypeCode', 'unknown')}")
            
            # Fetch event description for Bedrock analysis
            event_arn = event_data.get("arn", "")
            description = "No description available"
            
            if event_arn and account_batch:
                try:
                    # Fetch event details using first account to get description
                    health_data = fetch_health_event_details_for_org(event_arn, account_batch[0])
                    description = (
                        health_data.get("details", {})
                        .get("eventDescription", {})
                        .get("latestDescription", "No description available")
                    )
                    if not description:
                        description = "No description available"
                except Exception as e:
                    logging.warning(f"Could not fetch description for Bedrock analysis: {str(e)}")
                    description = "No description available"
            
            # Create event data structure for analysis
            event_for_analysis = {
                "eventTypeCode": event_data.get("eventTypeCode", "Unknown"),
                "eventTypeCategory": event_data.get("eventTypeCategory", "Unknown"),
                "region": event_data.get("region", "global"),
                "startTime": event_data.get("startTime", ""),
                "description": description,
                "service": event_data.get("service", "Unknown"),
            }
            
            # Perform Bedrock analysis
            try:
                analyzed_event = analyze_event_with_bedrock(bedrock_client, event_for_analysis)
                analysis = analyzed_event.get("analysis_text", "")
                categories = categorize_analysis(analyzed_event)
                
                # If analysis_text is empty, use impactAnalysis as fallback
                if not analysis or analysis.strip() == "":
                    logging.warning(f"Bedrock returned empty analysis_text, using impactAnalysis as fallback")
                    analysis = categories.get("impact_analysis", "Analysis data stored in category fields")
                
                logging.info(
                    f"Bedrock analysis complete: risk_level={categories.get('risk_level', 'unknown')}, "
                    f"critical={categories.get('critical', False)}"
                )
            except Exception as e:
                logging.error(f"Error performing Bedrock analysis in SQS worker: {str(e)}")
                # Use fallback values
                analysis = "Analysis failed in SQS worker"
                categories = {
                    "critical": False,
                    "risk_level": "LOW",
                    "impact_analysis": "Analysis failed",
                    "required_actions": "Review event manually",
                    "time_sensitivity": "Routine",
                    "risk_category": "Unknown",
                    "consequences_if_ignored": "",
                    "event_impact_type": "Informational",
                    "account_impact": "low",
                }
        
        # NEW: Fetch per-account status for all accounts in this batch
        event_arn = event_data.get("arn", "")
        event_level_status = event_data.get("statusCode", "open")  # Get event-level status for fallback
        account_statuses = {}
        
        if event_arn and account_batch:
            try:
                logging.info(f"Fetching per-account status for {len(account_batch)} accounts (event-level status: {event_level_status})")
                account_statuses = fetch_per_account_status_batch(
                    event_arn,
                    account_batch,
                    event_level_status=event_level_status,  # Pass event-level status as fallback
                    batch_size=10  # All accounts in this batch (max 10 per SQS message)
                )
                logging.info(f"Successfully fetched per-account status: {account_statuses}")
            except Exception as e:
                logging.error(f"Error fetching per-account status: {str(e)}")
                # Fallback: use event-level status for all accounts
                account_statuses = {
                    account_id: event_level_status
                    for account_id in account_batch
                }
                logging.warning(f"Using event-level status fallback: {event_level_status}")
        else:
            # Fallback: use event-level status if no event ARN
            logging.warning("No event ARN or accounts, using event-level status fallback")
            account_statuses = {
                account_id: event_level_status
                for account_id in account_batch
            }
        
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
                
                # Get per-account status (with fallback to event-level status)
                account_status = account_statuses.get(
                    account_id,
                    event_level_status  # Use event-level status instead of "unknown"
                )
                
                logging.debug(f"Account {account_id}: status={account_status}")
                
                # Build event record with SHARED analysis and FETCHED description
                event_entry = {
                    "arn": event_data.get("arn", "N/A"),
                    "eventArn": event_data.get("eventArn", event_data.get("arn", "N/A")),
                    "event_type": event_data.get("eventTypeCode", "N/A"),
                    "service": event_data.get("service", "N/A"),
                    "description": description,  # FETCHED from Health API
                    "region": event_region,
                    "start_time": format_date_only(event_data.get("startTime", "N/A")),
                    "last_update_time": format_datetime(event_data.get("lastUpdatedTime", "N/A")),
                    "status_code": account_status,  # PER-ACCOUNT STATUS!
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
            
            # Batch write to DynamoDB
            storage_result = store_events_in_dynamodb(events_analysis)
            
            # NOTE: Counts are NOT updated here to avoid performance issues.
            # ARN-based counts require checking ALL accounts for each ARN to determine
            # if the ARN is fully closed. This is done during scheduled_sync instead.
            # The counts will be slightly stale (up to sync interval) but accurate.
            logging.debug("Skipping counts update in SQS - will be handled by scheduled sync")
            
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
            # Store in DynamoDB
            storage_result = store_events_in_dynamodb(events_analysis)

            # NOTE: Counts are NOT updated here to avoid performance issues.
            # ARN-based counts require checking ALL accounts for each ARN.
            # This is done during scheduled_sync instead.
            logging.debug("Skipping counts update in SQS - will be handled by scheduled sync")

            logging.info(
                f"Successfully processed individual event (legacy format): stored={storage_result.get('stored', 0)}, updated={storage_result.get('updated', 0)}"
            )

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
