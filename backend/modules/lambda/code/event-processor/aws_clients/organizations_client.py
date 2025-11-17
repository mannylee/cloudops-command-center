import boto3
import logging

# Dictionary to store account ID to name mapping
account_id_to_name_map = {}


def get_account_name(account_id):
    """
    Get account name for a given account ID using AWS Organizations API

    Args:
        account_id (str): AWS account ID

    Returns:
        str: Account name or account ID if name can't be retrieved
    """
    # Check if we already have this account name in our cache
    if account_id in account_id_to_name_map:
        return account_id_to_name_map[account_id]

    try:
        # Try to get account name from Organizations API
        org_client = boto3.client("organizations")
        response = org_client.describe_account(AccountId=account_id)
        account_name = response.get("Account", {}).get("Name", account_id)

        # Cache the result
        account_id_to_name_map[account_id] = account_name
        return account_name
    except Exception as e:
        logging.warning(
            f"Error getting account name for {account_id}: {str(e)}"
        )
        # If we can't get the name, just return the ID
        account_id_to_name_map[account_id] = account_id
        return account_id
