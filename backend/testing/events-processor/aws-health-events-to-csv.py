#!/usr/bin/env python3
"""
AWS Health Events to CSV Script (Python Version)

This Python script replicates the functionality of the zsh script and Lambda event processor
but outputs health events to a CSV file instead of storing them in DynamoDB.

Note: All AWS Health API calls are made to us-east-1 region as required by the service
"""

import argparse
import boto3
import csv
import json
import logging
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple, Any

# Default configuration
DEFAULT_ANALYSIS_WINDOW_DAYS = 90
DEFAULT_EVENT_CATEGORIES = "all"
# Output directory relative to script location
DEFAULT_OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")
DEFAULT_BEDROCK_MODEL = "anthropic.claude-3-sonnet-20240229-v1:0"
DEFAULT_BEDROCK_TEMPERATURE = 0.1
DEFAULT_BEDROCK_TOP_P = 0.9
DEFAULT_BEDROCK_MAX_TOKENS = 4000

# AWS region for Health API (required to be us-east-1)
AWS_HEALTH_REGION = "us-east-1"

# CSV headers
CSV_HEADERS = [
    "eventArn",
    "accountId",
    "accountName",
    "affectedResources",
    "analysisTimestamp",
    "analysisVersion",
    "Category",
    "consequencesIfIgnored",
    "critical",
    "description",
    "eventImpactType",
    "eventType",
    "eventTypeCategory",
    "impactAnalysis",
    "lastUpdateTime",
    "region",
    "requiredActions",
    "riskCategory",
    "riskLevel",
    "service",
    "simplifiedDescription",
    "startTime",
    "statusCode",
    "timeSensitivity",
    "ttl",
]


class HealthEventsProcessor:
    """Main class for processing AWS Health events and generating CSV output."""

    def __init__(self, args):
        self.args = args
        self.setup_logging()
        self.setup_aws_clients()
        self.temp_dir = tempfile.mkdtemp(prefix="health-events-")

        # Ensure output directory is relative to script location
        self._resolve_output_path()

        # Data storage
        self.org_accounts = {}
        self.events = []
        self.expanded_events = []
        self.affected_resources = {}

    def setup_logging(self):
        """Configure logging with colored output."""
        logging.basicConfig(
            level=logging.INFO,
            format="%(message)s",
            handlers=[logging.StreamHandler(sys.stdout)],
        )
        self.logger = logging.getLogger(__name__)

    def _resolve_output_path(self):
        """Resolve output directory path relative to script location if it's a relative path."""
        if not os.path.isabs(self.args.output_dir):
            # If it's a relative path, make it relative to the script location
            script_dir = os.path.dirname(os.path.abspath(__file__))
            self.args.output_dir = os.path.join(script_dir, self.args.output_dir)

    def log_info(self, message: str):
        """Log info message with blue color."""
        print(f"\033[0;34m[INFO]\033[0m {message}")

    def log_success(self, message: str):
        """Log success message with green color."""
        print(f"\033[0;32m[SUCCESS]\033[0m {message}")

    def log_warning(self, message: str):
        """Log warning message with yellow color."""
        print(f"\033[1;33m[WARNING]\033[0m {message}")

    def log_error(self, message: str):
        """Log error message with red color."""
        print(f"\033[0;31m[ERROR]\033[0m {message}")

    def setup_aws_clients(self):
        """Initialize AWS clients."""
        try:
            self.health_client = boto3.client("health", region_name=AWS_HEALTH_REGION)
            self.organizations_client = boto3.client(
                "organizations", region_name=AWS_HEALTH_REGION
            )
            self.sts_client = boto3.client("sts", region_name=AWS_HEALTH_REGION)

            if self.args.bedrock:
                self.bedrock_client = boto3.client(
                    "bedrock-runtime", region_name=AWS_HEALTH_REGION
                )
                self.bedrock_list_client = boto3.client(
                    "bedrock", region_name=AWS_HEALTH_REGION
                )

        except Exception as e:
            self.log_error(f"Failed to initialize AWS clients: {e}")
            sys.exit(1)

    def check_dependencies(self):
        """Check AWS credentials and Bedrock access if enabled."""
        self.log_info("Checking dependencies...")

        # Check AWS credentials
        try:
            self.sts_client.get_caller_identity()
            self.log_success("AWS credentials verified")
        except Exception as e:
            self.log_error(f"AWS credentials not configured or invalid: {e}")
            sys.exit(1)

        # Check organization health dashboard access
        try:
            self.health_client.describe_events_for_organization(maxResults=1)
        except Exception as e:
            self.log_error(
                f"Organization Health Dashboard not enabled or no permissions: {e}"
            )
            sys.exit(1)

        # Check Bedrock access if enabled
        if self.args.bedrock:
            self.log_info("Checking Bedrock access...")
            try:
                self.bedrock_list_client.list_foundation_models()
                self.log_success("Bedrock access verified")

                # Verify the specific model is available
                models = self.bedrock_list_client.list_foundation_models()
                available_models = [
                    model["modelId"] for model in models["modelSummaries"]
                ]
                if self.args.model not in available_models:
                    self.log_warning(
                        f"Model {self.args.model} may not be available. Continuing anyway..."
                    )

            except Exception as e:
                self.log_error(f"Bedrock access not available: {e}")
                sys.exit(1)

        self.log_success("All dependencies are available")

    def setup_output(self):
        """Create output directory and CSV file with headers."""
        self.log_info("Setting up output directory...")

        os.makedirs(self.args.output_dir, exist_ok=True)

        # Create CSV file with headers
        output_path = os.path.join(self.args.output_dir, self.args.output_file)
        with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
            writer = csv.writer(csvfile, quoting=csv.QUOTE_ALL)
            writer.writerow(CSV_HEADERS)

        self.log_success(f"Output directory created: {self.args.output_dir}")

    def get_org_accounts(self):
        """Fetch organization accounts."""
        self.log_info("Fetching organization accounts...")

        try:
            # Get all accounts in the organization
            paginator = self.organizations_client.get_paginator("list_accounts")
            accounts = []

            for page in paginator.paginate():
                accounts.extend(page["Accounts"])

            # Create account lookup dictionary
            for account in accounts:
                self.org_accounts[account["Id"]] = account["Name"]

            active_count = sum(1 for acc in accounts if acc["Status"] == "ACTIVE")
            inactive_count = len(accounts) - active_count

            self.log_success(
                f"Retrieved {len(accounts)} organization accounts ({active_count} active, {inactive_count} inactive)"
            )

            # Debug: Show first few accounts
            self.log_info("Sample accounts from parsed data:")
            for i, (account_id, account_name) in enumerate(
                list(self.org_accounts.items())[:3]
            ):
                self.log_info(f"  {account_id} -> '{account_name}'")

        except Exception as e:
            self.log_warning(
                f"Could not fetch organization accounts, using current account only: {e}"
            )
            try:
                current_account = self.sts_client.get_caller_identity()["Account"]
                self.org_accounts[current_account] = "Current Account"
                self.log_info(
                    f"Using current account: {current_account} -> Current Account"
                )
            except Exception as e2:
                self.log_error(f"Failed to get current account: {e2}")
                sys.exit(1)

        self.log_success("Account information retrieved")

    def generate_simplified_description(self, service: str, event_type: str) -> str:
        """Generate simplified description based on service and event type."""
        if not service or service == "N/A":
            service = "AWS"

        event_type_upper = event_type.upper()

        if "OPERATIONAL_ISSUE" in event_type_upper:
            return f"{service} - Service disruptions or performance problems"
        elif "SECURITY_NOTIFICATION" in event_type_upper:
            return f"{service} - Security-related alerts and warnings"
        elif "PLANNED_LIFECYCLE_EVENT" in event_type_upper:
            return f"{service} - Lifecycle changes requiring action"
        elif any(
            x in event_type_upper
            for x in [
                "MAINTENANCE_SCHEDULED",
                "SYSTEM_MAINTENANCE",
                "PATCHING_RETIREMENT",
            ]
        ):
            return f"{service} - Routine Maintenance"
        elif "UPDATE_AVAILABLE" in event_type_upper:
            return f"{service} - Available software or system updates"
        elif "VPN_CONNECTIVITY" in event_type_upper:
            return "VPN tunnel or connection status alert"
        elif "BILLING_NOTIFICATION" in event_type_upper:
            return f"{service} - Billing or Cost change notification"
        else:
            return f"{service} - Service-specific events"

    def analyze_event_with_bedrock(self, event_data: Dict) -> Optional[Dict]:
        """Analyze event using Amazon Bedrock."""
        event_type = event_data.get("eventTypeCode", "Unknown")
        event_category = event_data.get("eventTypeCategory", "Unknown")
        region = event_data.get("region", "Unknown")
        start_time = event_data.get("startTime", "Unknown")
        description = event_data.get("description", "No description available")

        # Create the prompt
        prompt = f"""You are an AWS expert specializing in outage analysis and business continuity. Your task is to analyze this AWS Health event and determine its potential impact on workload availability, system connectivity, and service outages.

AWS Health Event:
- Type: {event_type}
- Category: {event_category}
- Region: {region}
- Start Time: {start_time}

Event Description:
{description}

IMPORTANT ANALYSIS FOCUS:
1. Will this event cause workload downtime if required actions are not taken?
2. Will there be any service outages associated with this event?
3. Will the application/workload experience network integration issues between connecting systems?
4. What specific AWS services or resources could be impacted?

CRITICAL EVENT CRITERIA:
- Any event that will cause service downtime should be marked as CRITICAL
- Any event that will cause network integration or SSL issues between systems should be marked as CRITICAL
- Any event that requires immediate action to prevent outage should be marked as URGENT time sensitivity
- Events with high impact but no immediate downtime should be marked as HIGH risk level

Please analyze this event and provide the following information in JSON format:
{{
  "critical": boolean,
  "risk_level": "CRITICAL|HIGH|MEDIUM|LOW",
  "account_impact": "critical|high|medium|low",
  "time_sensitivity": "Routine|Urgent|Critical",
  "risk_category": "Availability|Security|Performance|Cost|Compliance",
  "required_actions": "string",
  "impact_analysis": "string",
  "consequences_if_ignored": "string",
  "affected_resources": "string",
  "event_impact_type": "Service Outage|Billing Impact|Security Issue|Performance Degradation|Maintenance|Informational"
}}

IMPORTANT: In your impact_analysis field, be very specific about:
1. Potential outages and their estimated duration
2. Connectivity issues between systems
3. Whether this will cause downtime if actions are not taken

In your consequences_if_ignored field, clearly state what outages or disruptions will occur if the event is not addressed.

RISK LEVEL GUIDELINES:
- CRITICAL: Will cause service outage or severe disruption if not addressed
- HIGH: Significant impact but not an immediate outage
- MEDIUM: Moderate impact requiring attention
- LOW: Minimal impact, routine maintenance

EVENT IMPACT TYPE GUIDELINES:
- Service Outage: Event will cause or is causing service unavailability
- Billing Impact: Event affects billing or costs
- Security Issue: Event relates to security vulnerabilities or threats
- Performance Degradation: Event causes reduced performance but not complete outage
- Maintenance: Planned maintenance with minimal impact
- Informational: General information with no direct impact"""

        # Prepare Bedrock request payload
        if "claude-3" in self.args.model:
            # Claude 3 format
            payload = {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": self.args.max_tokens,
                "temperature": self.args.temperature,
                "top_p": self.args.top_p,
                "messages": [{"role": "user", "content": prompt}],
            }
        else:
            # Claude 2 format
            payload = {
                "prompt": f"\n\nHuman: {prompt}\n\nAssistant:",
                "max_tokens_to_sample": self.args.max_tokens,
                "temperature": self.args.temperature,
                "top_p": self.args.top_p,
            }

        # Call Bedrock with retry logic
        max_retries = 3
        for retry_count in range(max_retries):
            try:
                response = self.bedrock_client.invoke_model(
                    modelId=self.args.model,
                    contentType="application/json",
                    accept="application/json",
                    body=json.dumps(payload),
                )

                response_body = json.loads(response["body"].read())

                # Extract response text based on model type
                if "claude-3" in self.args.model:
                    response_text = response_body.get("content", [{}])[0].get(
                        "text", ""
                    )
                else:
                    response_text = response_body.get("completion", "")

                # Extract JSON from response
                json_match = re.search(
                    r"```json\s*(\{.*?\})\s*```", response_text, re.DOTALL
                )
                if json_match:
                    json_content = json_match.group(1)
                else:
                    # Try to find JSON without code blocks
                    json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
                    if json_match:
                        json_content = json_match.group(0)
                    else:
                        json_content = None

                if json_content:
                    try:
                        return json.loads(json_content)
                    except json.JSONDecodeError:
                        pass

                break

            except Exception as e:
                if retry_count < max_retries - 1:
                    self.log_warning(
                        f"Bedrock request failed, retrying in {(retry_count + 1) * 2} seconds..."
                    )
                    time.sleep((retry_count + 1) * 2)
                else:
                    self.log_warning(
                        f"Bedrock analysis failed after {max_retries} retries: {e}"
                    )

        return None

    def categorize_event(
        self, description: str, event_type: str, service: str, status: str
    ) -> Dict:
        """Simple analysis categorization (fallback when Bedrock is not used or fails)."""
        # Default values
        analysis = {
            "critical": False,
            "risk_level": "LOW",
            "time_sensitivity": "Routine",
            "risk_category": "Unknown",
            "event_impact_type": "Informational",
            "required_actions": "",
            "impact_analysis": "",
            "consequences_if_ignored": "",
        }

        description_lower = description.lower()
        event_type_upper = event_type.upper()

        # Analyze based on keywords and patterns
        if any(
            keyword in description_lower
            for keyword in ["security", "vulnerability", "breach"]
        ):
            analysis.update(
                {
                    "critical": True,
                    "risk_level": "HIGH",
                    "time_sensitivity": "Urgent",
                    "risk_category": "Security",
                    "event_impact_type": "Security Issue",
                }
            )
        elif any(
            keyword in description_lower
            for keyword in ["outage", "disruption", "unavailable"]
        ):
            analysis.update(
                {
                    "critical": True,
                    "risk_level": "HIGH",
                    "time_sensitivity": "Critical",
                    "risk_category": "Availability",
                    "event_impact_type": "Service Outage",
                }
            )
        elif any(
            keyword in description_lower for keyword in ["maintenance", "scheduled"]
        ):
            analysis.update(
                {
                    "risk_level": "MEDIUM",
                    "time_sensitivity": "Routine",
                    "risk_category": "Maintenance",
                    "event_impact_type": "Maintenance",
                }
            )
        elif any(keyword in description_lower for keyword in ["billing", "cost"]):
            analysis.update(
                {
                    "risk_level": "LOW",
                    "time_sensitivity": "Routine",
                    "risk_category": "Cost",
                    "event_impact_type": "Billing Impact",
                }
            )

        # Adjust based on event type
        if "SECURITY" in event_type_upper:
            analysis.update(
                {
                    "critical": True,
                    "risk_level": "HIGH",
                    "risk_category": "Security",
                    "event_impact_type": "Security Issue",
                }
            )
        elif "OPERATIONAL_ISSUE" in event_type_upper:
            analysis.update(
                {
                    "risk_level": "HIGH",
                    "risk_category": "Availability",
                    "event_impact_type": "Service Outage",
                }
            )
        elif "LIFECYCLE" in event_type_upper:
            analysis.update(
                {
                    "risk_level": "MEDIUM",
                    "risk_category": "Compliance",
                    "event_impact_type": "Maintenance",
                }
            )

        # Generate basic required actions
        if analysis["critical"]:
            analysis["required_actions"] = (
                "Review and take immediate action as described in the event details."
            )
        else:
            analysis["required_actions"] = (
                "Review the event details and plan appropriate actions."
            )

        # Generate impact analysis
        if status == "open":
            analysis["impact_analysis"] = (
                "This is an active event that may be impacting your AWS resources."
            )
        else:
            analysis["impact_analysis"] = (
                "This event provides information about your AWS resources."
            )

        # Generate consequences
        if analysis["critical"]:
            analysis["consequences_if_ignored"] = (
                "Ignoring this event may result in security vulnerabilities or service disruptions."
            )
        else:
            analysis["consequences_if_ignored"] = (
                "This event is informational and may not require immediate action."
            )

        return analysis

    def fetch_health_events(self):
        """Fetch health events from AWS Health API."""
        self.log_info(f"Fetching health events for the last {self.args.days} days...")

        # Calculate date range
        end_time = datetime.now(timezone.utc)
        start_time = end_time - timedelta(days=self.args.days)

        self.log_info(f"Date range: {start_time.isoformat()} to {end_time.isoformat()}")
        self.log_info(f"Event categories filter: '{self.args.categories}'")

        try:
            # Build filter
            filter_dict = {"lastUpdatedTime": {"from": start_time, "to": end_time}}

            # Add category filter if not "all"
            if self.args.categories != "all" and self.args.categories:
                categories = [cat.strip() for cat in self.args.categories.split(",")]
                filter_dict["eventTypeCategories"] = categories
                self.log_info(f"Fetching events with category filter: {categories}")
            else:
                self.log_info(
                    "Fetching ALL event categories (no category filtering)..."
                )

            # Fetch events with pagination
            paginator = self.health_client.get_paginator(
                "describe_events_for_organization"
            )
            all_events = []

            for page in paginator.paginate(filter=filter_dict, maxResults=100):
                all_events.extend(page.get("events", []))

            # Also fetch currently active events (no end time filter)
            self.log_info("Fetching currently active events...")
            active_filter = {"lastUpdatedTime": {"from": start_time}}

            if self.args.categories != "all" and self.args.categories:
                active_filter["eventTypeCategories"] = categories

            for page in paginator.paginate(filter=active_filter, maxResults=100):
                all_events.extend(page.get("events", []))

            # Remove duplicates based on ARN
            seen_arns = set()
            unique_events = []
            for event in all_events:
                if event["arn"] not in seen_arns:
                    seen_arns.add(event["arn"])
                    unique_events.append(event)

            self.events = unique_events
            self.log_success(f"Retrieved {len(self.events)} events")

            # Debug: Show unique event categories found
            categories_found = set()
            for event in self.events:
                if "eventTypeCategory" in event:
                    categories_found.add(event["eventTypeCategory"])

            if categories_found:
                self.log_info(
                    f"Event categories found: {', '.join(sorted(categories_found))}"
                )
            else:
                self.log_warning("No event categories found in results")

            # Debug: Show sample events
            self.log_info("Sample events found:")
            sample_events = [
                e
                for e in self.events
                if any(
                    service in e.get("eventTypeCode", "")
                    for service in ["LAMBDA", "EKS", "ATHENA", "ES"]
                )
            ][:5]
            for event in sample_events:
                self.log_info(
                    f"  {event.get('eventTypeCode')} - {event.get('region')} - {event.get('lastUpdatedTime')}"
                )

        except Exception as e:
            self.log_error(f"Failed to fetch health events: {e}")
            sys.exit(1)

    def get_affected_accounts(self):
        """Get affected accounts for each event and expand events."""
        self.log_info("Getting affected accounts for each event...")

        event_count = len(self.events)
        self.expanded_events = []

        for i, event in enumerate(self.events, 1):
            event_arn = event["arn"]
            event_type = event.get("eventTypeCode", "Unknown")

            self.log_info(f"Processing event {i}/{event_count}: {event_type}")

            try:
                # Get affected accounts for this event
                response = (
                    self.health_client.describe_affected_accounts_for_organization(
                        eventArn=event_arn
                    )
                )
                affected_accounts = response.get("affectedAccounts", [])

                if not affected_accounts:
                    self.log_warning(f"No affected accounts for event: {event_type}")
                    continue

                # Create separate event record for each affected account
                for account_id in affected_accounts:
                    expanded_event = event.copy()
                    expanded_event["accountId"] = account_id
                    self.expanded_events.append(expanded_event)

            except Exception as e:
                self.log_warning(
                    f"Failed to get affected accounts for event {event_arn}: {e}"
                )
                continue

        self.log_success(
            f"Expanded to {len(self.expanded_events)} account-specific events"
        )

    def get_affected_resources(self):
        """Get affected resources for events."""
        self.log_info("Getting affected resources for events...")

        total_events = len(self.expanded_events)

        for i, event in enumerate(self.expanded_events, 1):
            event_arn = event["arn"]
            account_id = event["accountId"]

            # Show progress every 10 events
            if i % 10 == 0:
                self.log_info(
                    f"Processing affected resources: {i}/{total_events} events..."
                )

            # Debug: Show what we're querying for (first few events only)
            if i <= 3:
                self.log_info(
                    f"Querying affected resources for event: {event_arn}, account: {account_id}"
                )

            try:
                # Get affected entities for this event and account
                response = (
                    self.health_client.describe_affected_entities_for_organization(
                        organizationEntityFilters=[
                            {"eventArn": event_arn, "awsAccountId": account_id}
                        ]
                    )
                )

                entities = response.get("entities", [])
                entity_values = [entity.get("entityValue", "") for entity in entities]

                # Debug: Show what we got back (first few events only)
                if i <= 3:
                    self.log_info(
                        f"Found {len(entity_values)} affected entities for this event"
                    )
                    if entity_values:
                        self.log_info(f"Sample entities: {' '.join(entity_values[:2])}")

                # Store resources as comma-separated string
                resources = (
                    ", ".join(entity_values) if entity_values else "None specified"
                )
                key = f"{event_arn}|{account_id}"
                self.affected_resources[key] = resources

            except Exception as e:
                self.log_warning(
                    f"Failed to get affected resources for event {event_arn}, account {account_id}: {e}"
                )
                key = f"{event_arn}|{account_id}"
                self.affected_resources[key] = "None specified"

        self.log_success("Affected resources retrieved")

    def process_events_to_csv(self):
        """Process events and generate CSV output."""
        self.log_info("Processing events and generating CSV...")

        analysis_timestamp = datetime.now(timezone.utc).isoformat()
        output_path = os.path.join(self.args.output_dir, self.args.output_file)

        with open(output_path, "a", newline="", encoding="utf-8") as csvfile:
            writer = csv.writer(csvfile, quoting=csv.QUOTE_ALL)

            for i, event in enumerate(self.expanded_events, 1):
                # Extract event data
                event_arn = event["arn"]
                account_id = event["accountId"]
                event_type = event.get("eventTypeCode", "")
                event_type_category = event.get("eventTypeCategory", "")
                service = event.get("service", "")
                region = event.get("region", "")
                start_time = event.get("startTime", "")
                last_update_time = event.get("lastUpdatedTime", "")
                status_code = event.get("statusCode", "")

                # Get description from eventDescription or fallback
                event_desc = event.get("eventDescription", {})
                if isinstance(event_desc, dict):
                    description = event_desc.get(
                        "latestDescription", "No description available"
                    )
                else:
                    description = (
                        str(event_desc) if event_desc else "No description available"
                    )

                # Get account name with fallback
                account_name = self.org_accounts.get(account_id, "Unknown")

                # Debug: Show account lookup (only for first few events)
                if i <= 3:
                    self.log_info(f"Looking up account ID: '{account_id}'")
                    self.log_info(f"Found account name: '{account_name}'")

                # Get affected resources
                resource_key = f"{event_arn}|{account_id}"
                affected_resources = self.affected_resources.get(
                    resource_key, "None specified"
                )

                # Generate simplified description
                simplified_description = self.generate_simplified_description(
                    service, event_type
                )

                # Analyze event (Bedrock or fallback)
                analysis = None
                if self.args.bedrock:
                    event_data = {
                        "eventTypeCode": event_type,
                        "eventTypeCategory": event_type_category,
                        "region": region,
                        "startTime": str(start_time),
                        "description": description,
                    }
                    analysis = self.analyze_event_with_bedrock(event_data)

                if not analysis:
                    analysis = self.categorize_event(
                        description, event_type, service, status_code
                    )

                # Calculate TTL (6 months from last update)
                try:
                    if isinstance(last_update_time, str):
                        last_update_dt = datetime.fromisoformat(
                            last_update_time.replace("Z", "+00:00")
                        )
                    else:
                        last_update_dt = last_update_time
                    ttl_dt = last_update_dt + timedelta(days=180)
                    ttl = int(ttl_dt.timestamp())
                except:
                    ttl = int(
                        (datetime.now(timezone.utc) + timedelta(days=180)).timestamp()
                    )

                # Convert datetime objects to strings for CSV
                start_time_str = str(start_time) if start_time else ""
                last_update_time_str = str(last_update_time) if last_update_time else ""

                # Write CSV row
                row = [
                    event_arn,
                    account_id,
                    account_name,
                    affected_resources,
                    analysis_timestamp,
                    "1.0",  # analysisVersion
                    "",  # Category (reserved for future use)
                    analysis.get("consequences_if_ignored", ""),
                    str(analysis.get("critical", False)).lower(),
                    description,
                    analysis.get("event_impact_type", ""),
                    event_type,
                    event_type_category,
                    analysis.get("impact_analysis", ""),
                    last_update_time_str,
                    region,
                    analysis.get("required_actions", ""),
                    analysis.get("risk_category", ""),
                    analysis.get("risk_level", ""),
                    service,
                    simplified_description,
                    start_time_str,
                    status_code,
                    analysis.get("time_sensitivity", ""),
                    str(ttl),
                ]

                writer.writerow(row)

        self.log_success(f"CSV file generated: {output_path}")
        self.log_success(f"Processed {len(self.expanded_events)} events")

    def cleanup(self):
        """Clean up temporary files."""
        try:
            import shutil

            shutil.rmtree(self.temp_dir, ignore_errors=True)
        except:
            pass

    def run(self):
        """Main execution method."""
        try:
            self.check_dependencies()
            self.setup_output()
            self.get_org_accounts()
            self.fetch_health_events()

            if not self.events:
                self.log_warning("No events found in the specified time range")
                return

            self.get_affected_accounts()

            if not self.expanded_events:
                self.log_warning("No events with affected accounts found")
                return

            self.get_affected_resources()
            self.process_events_to_csv()

        except KeyboardInterrupt:
            self.log_warning("Process interrupted by user")
            sys.exit(1)
        except Exception as e:
            self.log_error(f"Unexpected error: {e}")
            sys.exit(1)
        finally:
            self.cleanup()


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="AWS Health Events to CSV Script - Replicates Lambda event processor functionality",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
    # Basic usage with default settings
    python %(prog)s

    # Custom analysis window and specific categories
    python %(prog)s -d 14 -c "issue,scheduledChange"

    # Enable Bedrock analysis with custom model
    python %(prog)s -b -m "anthropic.claude-3-haiku-20240307-v1:0"

    # Full customization with all events
    python %(prog)s -d 30 -c "all" -o ./reports -b -t 0.2

EVENT CATEGORIES:
    - all: Fetch all event types (default)
    - issue: Service disruptions and operational issues
    - scheduledChange: Planned maintenance and changes
    - accountNotification: Account-level notifications
    - Or specify multiple: "issue,scheduledChange"

BEDROCK MODELS:
    - anthropic.claude-3-sonnet-20240229-v1:0 (default, balanced)
    - anthropic.claude-3-haiku-20240307-v1:0 (faster, cheaper)
    - anthropic.claude-3-opus-20240229-v1:0 (most capable, expensive)
        """,
    )

    parser.add_argument(
        "-d",
        "--days",
        type=int,
        default=DEFAULT_ANALYSIS_WINDOW_DAYS,
        help=f"Analysis window in days (default: {DEFAULT_ANALYSIS_WINDOW_DAYS})",
    )

    parser.add_argument(
        "-c",
        "--categories",
        default=DEFAULT_EVENT_CATEGORIES,
        help=f'Comma-separated event categories or "all" for no filtering (default: {DEFAULT_EVENT_CATEGORIES})',
    )

    parser.add_argument(
        "-o",
        "--output-dir",
        default=DEFAULT_OUTPUT_DIR,
        help="Output directory (default: ./output relative to script location)",
    )

    parser.add_argument(
        "-f",
        "--output-file",
        default=f"health-events-{datetime.now().strftime('%Y-%m-%d_%H-%M')}.csv",
        help="Output filename (default: health-events-YYYY-MM-DD_HH-MM.csv)",
    )

    parser.add_argument(
        "-b", "--bedrock", action="store_true", help="Enable Bedrock AI analysis"
    )

    parser.add_argument(
        "-m",
        "--model",
        default=DEFAULT_BEDROCK_MODEL,
        help=f"Bedrock model ID (default: {DEFAULT_BEDROCK_MODEL})",
    )

    parser.add_argument(
        "-t",
        "--temperature",
        type=float,
        default=DEFAULT_BEDROCK_TEMPERATURE,
        help=f"Bedrock temperature (default: {DEFAULT_BEDROCK_TEMPERATURE})",
    )

    parser.add_argument(
        "-p",
        "--top-p",
        type=float,
        default=DEFAULT_BEDROCK_TOP_P,
        help=f"Bedrock top-p (default: {DEFAULT_BEDROCK_TOP_P})",
    )

    parser.add_argument(
        "-x",
        "--max-tokens",
        type=int,
        default=DEFAULT_BEDROCK_MAX_TOKENS,
        help=f"Bedrock max tokens (default: {DEFAULT_BEDROCK_MAX_TOKENS})",
    )

    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_arguments()
    processor = HealthEventsProcessor(args)
    processor.run()


if __name__ == "__main__":
    main()
