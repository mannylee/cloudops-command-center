import boto3
import logging
from botocore.exceptions import ClientError
from utils.helpers import get_account_id_from_event


def get_health_client():
    """Get AWS Health client"""
    return boto3.client("health", region_name="us-east-1")


def is_org_view_enabled():
    """
    Check if AWS Health Organization View is enabled

    Returns:
        bool: True if organization view is enabled, False otherwise
    """
    try:
        # Try to call an organization-specific API to check if it's enabled
        health_client = get_health_client()
        logging.debug(
            f"Testing organization view with health client in region: {health_client.meta.region_name}"
        )
        # This will throw an exception if org view is not enabled
        health_client.describe_events_for_organization(filter={}, maxResults=1)
        logging.info("Organization view test successful")
        return True
    except Exception as e:
        error_code = getattr(e, "response", {}).get("Error", {}).get("Code", "")
        error_message = getattr(e, "response", {}).get("Error", {}).get("Message", "")
        logging.warning(
            f"Organization view test failed - Error Code: {error_code}, Message: {error_message}"
        )
        if error_code == "SubscriptionRequiredException":
            return False
        # For any other error, assume we don't have org view permissions
        return False


def fetch_health_event_details(event_arn):
    """
    Fetch detailed event information from AWS Health API

    Args:
        event_arn (str): ARN of the health event

    Returns:
        dict: Event details including affected resources
    """
    try:
        health_client = get_health_client()

        # Get event details
        event_details = health_client.describe_event_details(eventArns=[event_arn])

        # Get affected entities
        affected_entities = health_client.describe_affected_entities(
            filter={"eventArns": [event_arn]}
        )

        return {
            "details": (
                event_details.get("successfulSet", [{}])[0]
                if event_details.get("successfulSet")
                else {}
            ),
            "entities": affected_entities.get("entities", []),
        }
    except Exception as e:
        logging.error(f"Error fetching Health API data: {str(e)}")
        return {"details": {}, "entities": []}


def fetch_affected_accounts_for_event(event_arn, max_accounts=None):
    """
    Fetch all affected accounts for an event with pagination support

    Args:
        event_arn (str): ARN of the health event
        max_accounts (int, optional): Maximum number of accounts to fetch (for testing/limits)

    Returns:
        list: List of affected account IDs
    """
    try:
        health_client = get_health_client()
        all_affected_accounts = []
        next_token = None
        page_count = 0

        while True:
            page_count += 1
            
            # Build request parameters
            request_params = {
                "eventArn": event_arn,
                "maxResults": 100  # Request maximum per page
            }
            
            if next_token:
                request_params["nextToken"] = next_token

            # Fetch affected accounts
            logging.debug(f"Fetching affected accounts page {page_count} for event {event_arn}")
            accounts_response = health_client.describe_affected_accounts_for_organization(
                **request_params
            )

            # Add accounts from this page
            page_accounts = accounts_response.get("affectedAccounts", [])
            all_affected_accounts.extend(page_accounts)
            
            logging.debug(f"Page {page_count}: Retrieved {len(page_accounts)} accounts (total: {len(all_affected_accounts)})")

            # Check if we've hit the max_accounts limit
            if max_accounts and len(all_affected_accounts) >= max_accounts:
                logging.info(f"Reached max_accounts limit of {max_accounts}, stopping pagination")
                all_affected_accounts = all_affected_accounts[:max_accounts]
                break

            # Check for more pages
            next_token = accounts_response.get("nextToken")
            if not next_token:
                logging.debug(f"No more pages, total accounts: {len(all_affected_accounts)}")
                break

        logging.info(f"Fetched {len(all_affected_accounts)} affected accounts for event {event_arn} across {page_count} page(s)")
        return all_affected_accounts

    except Exception as e:
        logging.error(f"Error fetching affected accounts for event {event_arn}: {str(e)}")
        return []


def map_entity_status_to_event_status(entity_status):
    """
    Map AWS Health entity status codes to event status codes.
    
    AWS Health API returns different status codes for entities vs events:
    - Entity status (from describe_affected_entities_for_organization):
      IMPAIRED, UNIMPAIRED, UNKNOWN, PENDING, RESOLVED
    - Event status (used in DynamoDB and describe_events_for_organization):
      open, closed, upcoming
    
    This function maps entity status to event status for consistency.
    
    Args:
        entity_status (str): Entity status code from AWS Health API
        
    Returns:
        str: Mapped event status code (open, closed, upcoming, or unknown)
    """
    # Normalize to uppercase for comparison
    entity_status_upper = str(entity_status).upper()
    
    # Map entity status to event status
    status_mapping = {
        'IMPAIRED': 'open',      # Resource is impaired = event is open
        'PENDING': 'open',       # Issue is pending = event is open
        'UNIMPAIRED': 'closed',  # Resource is unimpaired = event is closed
        'RESOLVED': 'closed',    # Issue is resolved = event is closed
        'UNKNOWN': 'unknown',    # Unknown status = unknown
    }
    
    mapped_status = status_mapping.get(entity_status_upper, 'unknown')
    
    if mapped_status == 'unknown' and entity_status_upper not in status_mapping:
        logging.warning(f"Unknown entity status '{entity_status}', mapping to 'unknown'")
    
    return mapped_status


def fetch_per_account_status_batch(event_arn, account_ids, event_level_status='open', batch_size=10):
    """
    Fetch status for multiple accounts with PAGINATION support.
    AWS Health API supports up to 10 organizationEntityFilters per call.
    
    This function is used by SQS workers to get per-account status for events,
    enabling accurate tracking of which accounts have resolved issues vs which still have open issues.
    
    IMPORTANT: This function fetches ENTITY status from AWS Health API and maps it to
    EVENT status codes (open/closed/upcoming) for consistency with DynamoDB schema.
    
    PAGINATION: Handles multiple pages of entities to ensure ALL affected resources are checked.
    Critical for events with 100+ entities where some may be IMPAIRED while others are RESOLVED.
    
    Args:
        event_arn (str): Event ARN
        account_ids (list): List of account IDs to fetch status for
        event_level_status (str): Fallback status if API fails (default: 'open')
        batch_size (int): Number of accounts per API call (max 10, AWS API limit)
        
    Returns:
        dict: {account_id: status_code}
            status_code will be: 'open', 'closed', 'upcoming' (never 'unknown' - uses event_level_status as fallback)
            (mapped from entity status: IMPAIRED/PENDING -> open, UNIMPAIRED/RESOLVED -> closed)
    """
    health_client = get_health_client()
    account_statuses = {}
    
    # CRITICAL FIX: If event is closed at event level, ALL accounts must be closed
    # This is a safety net to ensure closed events stay closed regardless of entity status
    # Event deadline has passed - no longer actionable even if some resources weren't addressed
    if event_level_status == 'closed':
        logging.info(
            f"Event {event_arn} is closed at event level. "
            f"Marking all {len(account_ids)} accounts as closed (skipping entity checks). "
            f"Reason: Event deadline passed - no longer actionable."
        )
        return {account_id: 'closed' for account_id in account_ids}
    
    if not account_ids:
        logging.warning("No account IDs provided to fetch_per_account_status_batch")
        return account_statuses
    
    # Split accounts into batches of batch_size (API limit is 10)
    for i in range(0, len(account_ids), batch_size):
        batch = account_ids[i:i + batch_size]
        
        # Build filters for this batch
        filters = [
            {'eventArn': event_arn, 'awsAccountId': account_id}
            for account_id in batch
        ]
        
        try:
            # PAGINATION LOOP - fetch ALL pages of entities
            next_token = None
            page_count = 0
            total_entities = 0
            max_pages = 10  # Safety limit to prevent infinite loops
            
            while True:
                page_count += 1
                
                # Safety check: prevent excessive pagination
                if page_count > max_pages:
                    logging.warning(
                        f"Reached max pagination limit ({max_pages} pages, {total_entities} entities). "
                        f"Some entities may not be processed. Consider increasing max_pages if needed."
                    )
                    break
                
                logging.debug(f"Fetching entities page {page_count} for {len(batch)} accounts")
                
                # Build API call parameters
                api_params = {
                    'organizationEntityFilters': filters,
                    'maxResults': 100  # Explicit max per page
                }
                
                if next_token:
                    api_params['nextToken'] = next_token
                
                response = health_client.describe_affected_entities_for_organization(**api_params)
                
                # Parse response - entities are grouped by account
                entities = response.get('entities', [])
                total_entities += len(entities)
                logging.debug(f"Page {page_count}: Received {len(entities)} entities (total so far: {total_entities})")
                
                # Process entities from this page
                for entity in entities:
                    account_id = entity.get('awsAccountId')
                    entity_status = entity.get('statusCode')
                    
                    if account_id:
                        if entity_status:
                            # Map entity status to event status
                            event_status = map_entity_status_to_event_status(entity_status)
                            
                            # CRITICAL: "Worst case wins" logic
                            # If account already has status, only update if new status is "worse"
                            # Priority: open > closed (open means action needed)
                            current_status = account_statuses.get(account_id)
                            
                            if current_status is None:
                                # First entity for this account
                                account_statuses[account_id] = event_status
                                logging.debug(f"Account {account_id}: entity_status={entity_status} -> event_status={event_status}")
                            elif current_status == 'closed' and event_status == 'open':
                                # Found an open entity, upgrade to open
                                account_statuses[account_id] = 'open'
                                logging.info(f"Account {account_id}: upgraded to 'open' (found IMPAIRED/PENDING entity on page {page_count})")
                            # If current is 'open', keep it (already worst case)
                        else:
                            # No statusCode in entity response
                            if account_id not in account_statuses:
                                # Only set if we haven't seen this account yet
                                account_statuses[account_id] = event_level_status
                                logging.debug(f"Account {account_id}: no statusCode in entity, using event-level status '{event_level_status}'")
                
                # OPTIMIZATION: Early exit if all accounts have "open" status
                # No need to check more pages since "open" is worst case
                if len(account_statuses) == len(batch) and all(status == 'open' for status in account_statuses.values()):
                    logging.info(
                        f"All {len(batch)} accounts have 'open' status after page {page_count}. "
                        f"Skipping remaining pages (optimization)."
                    )
                    break
                
                # Check for more pages
                next_token = response.get('nextToken')
                if not next_token:
                    logging.debug(f"No more pages, processed {page_count} page(s) with {total_entities} total entities")
                    break
            
            # After ALL pages, handle accounts with no entities
            for account_id in batch:
                if account_id not in account_statuses:
                    # No entities across ALL pages - use event-level status as fallback
                    # This is safer than assuming "closed" because:
                    # 1. API might have issues returning entities
                    # 2. Some event types don't expose entities via this API
                    # 3. Events past deadline may not return entities even if resources still affected
                    account_statuses[account_id] = event_level_status
                    logging.debug(
                        f"Account {account_id}: no entities across {page_count} page(s), "
                        f"using event-level status '{event_level_status}' as fallback"
                    )
                    
        except Exception as e:
            logging.error(f"Error fetching batch status for event {event_arn}: {str(e)}")
            # Use event-level status as fallback instead of 'unknown'
            for account_id in batch:
                if account_id not in account_statuses:
                    account_statuses[account_id] = event_level_status
                    logging.warning(f"Account {account_id}: API error, using event-level status '{event_level_status}' as fallback")
    
    logging.info(f"Fetched per-account status for {len(account_statuses)} accounts: {account_statuses}")
    return account_statuses


def fetch_health_event_details_for_org(event_arn, account_id=None):
    """
    Fetch detailed event information from AWS Health API for any account in the organization

    Args:
        event_arn (str): ARN of the health event
        account_id (str, optional): AWS account ID that owns the event

    Returns:
        dict: Event details including affected resources
    """
    try:
        health_client = get_health_client()

        # First try organization API (works for both current and linked accounts)
        try:
            # Prepare request for organization event details
            org_filter = {"eventArn": event_arn}

            # Add account ID if provided
            if account_id:
                org_filter["awsAccountId"] = account_id

            # Get event details using organization API
            org_event_details = health_client.describe_event_details_for_organization(
                organizationEventDetailFilters=[org_filter]
            )

            # Get affected entities using organization API
            org_affected_entities = (
                health_client.describe_affected_entities_for_organization(
                    organizationEntityFilters=[
                        {
                            "eventArn": event_arn,
                            "awsAccountId": (
                                account_id
                                if account_id
                                else get_account_id_from_event(event_arn)
                            ),
                        }
                    ]
                )
            )

            # Check if we got successful results
            if (
                org_event_details.get("successfulSet")
                and len(org_event_details["successfulSet"]) > 0
            ):
                return {
                    "details": org_event_details["successfulSet"][0],
                    "entities": org_affected_entities.get("entities", []),
                }

            # If we got here, organization API didn't return results
            logging.warning(
                f"Organization API didn't return results for event {event_arn}"
            )

        except Exception as org_error:
            logging.error(
                f"Error using organization API for event {event_arn}: {str(org_error)}"
            )

        # Fall back to account-specific API (only works for current account)
        logging.info(
            f"Falling back to account-specific API for event {event_arn}"
        )

        return fetch_health_event_details(event_arn)

    except Exception as e:
        logging.error(f"Error fetching Health API data: {str(e)}")
        return {"details": {}, "entities": []}


# get_account_id_from_event function imported from utils.helpers
