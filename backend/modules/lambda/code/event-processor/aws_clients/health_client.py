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
