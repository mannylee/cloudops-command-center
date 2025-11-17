import os

# Environment variables for configuration
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-20250514-v1:0"
)
BEDROCK_TEMPERATURE = float(os.environ.get("BEDROCK_TEMPERATURE", "0.1"))
BEDROCK_TOP_P = float(os.environ.get("BEDROCK_TOP_P", "0.9"))
BEDROCK_MAX_TOKENS = int(os.environ.get("BEDROCK_MAX_TOKENS", "4000"))
EXCLUDED_SERVICES = os.environ.get("EXCLUDED_SERVICES", "")
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_HEALTH_EVENTS_TABLE_NAME", "")
COUNTS_TABLE_NAME = os.environ.get("DYNAMODB_COUNTS_TABLE_NAME", "")
SPECIFIC_ACCOUNT_IDS = os.environ.get("SPECIFIC_ACCOUNT_IDS", "")

# Processed configurations
excluded_services = [s.strip() for s in EXCLUDED_SERVICES.split(",") if s.strip()]
specific_account_ids = [s.strip() for s in SPECIFIC_ACCOUNT_IDS.split(",") if s.strip()]
