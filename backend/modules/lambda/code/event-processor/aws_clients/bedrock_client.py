import boto3
import os

def get_bedrock_client():
    """
    Get Amazon Bedrock client
    
    Returns:
        boto3.client: Bedrock runtime client
    """
    # Use deployment region or fallback to us-east-1
    region = os.environ.get('AWS_REGION', 'us-east-1')
    return boto3.client(service_name='bedrock-runtime', region_name=region)