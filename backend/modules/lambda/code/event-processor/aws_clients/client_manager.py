"""
AWS client management and initialization
"""

import boto3
import os


def get_clients():
    """
    Get initialized AWS clients (cached per Lambda container)

    Returns:
        tuple: (health_client, bedrock_client, sqs_client)
    """
    # Health API must always use us-east-1 for organizational health events
    health_client = boto3.client("health", region_name="us-east-1")

    # Initialize Bedrock client - use deployment region or fallback to us-east-1
    bedrock_region = os.environ.get("AWS_REGION", os.environ.get("BEDROCK_REGION", "us-east-1"))
    bedrock_client = boto3.client("bedrock-runtime", region_name=bedrock_region)

    # Initialize SQS client for parallel processing - use current region
    sqs_client = boto3.client("sqs")

    return health_client, bedrock_client, sqs_client
