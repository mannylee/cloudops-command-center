import json
import logging
import os
import random
import re
import time
import traceback
import hashlib
from botocore.exceptions import ClientError

from utils.config import (
    BEDROCK_MODEL_ID,
    BEDROCK_TEMPERATURE,
    BEDROCK_TOP_P,
    BEDROCK_MAX_TOKENS,
)


def invoke_bedrock_with_advanced_retry(bedrock_client, payload, model_id):
    """
    Advanced retry mechanism for Bedrock API calls with concurrent processing optimization

    Features:
    - Extended retry attempts (10 instead of 5)
    - Staggered delays based on Lambda instance ID
    - Progressive backoff with higher maximum delays
    - Jitter to prevent thundering herd
    - Circuit breaker pattern for persistent failures

    Args:
        bedrock_client: Bedrock client instance
        payload: Request payload for Bedrock
        model_id: Model ID being used

    Returns:
        str: Response text from Bedrock
    """
    max_retries = 10  # Increased from 5
    base_delay = 2  # Increased base delay
    max_delay = 60  # Maximum delay cap

    # Create a unique stagger based on Lambda instance and event
    instance_id = os.environ.get("AWS_LAMBDA_LOG_STREAM_NAME", "unknown")
    event_hash = hashlib.md5(str(payload).encode()).hexdigest()[:8]
    stagger_seed = hash(f"{instance_id}-{event_hash}") % 1000
    initial_stagger = (stagger_seed / 1000) * 3  # 0-3 second initial stagger

    logging.debug(
        f"Starting Bedrock request with {initial_stagger:.2f}s initial stagger"
    )
    time.sleep(initial_stagger)

    consecutive_throttles = 0
    response_text = ""

    for attempt in range(max_retries):
        try:
            logging.debug(f"Bedrock attempt {attempt + 1}/{max_retries}")
            response = bedrock_client.invoke_model(**payload)
            response_body = json.loads(response.get("body").read())

            # Extract response based on model
            if any(
                model in model_id.lower()
                for model in ["claude-3", "claude-sonnet-4", "claude-3-7", "claude-3-5"]
            ):
                response_text = response_body.get("content", [{}])[0].get("text", "")
            else:
                response_text = response_body.get("completion", "")

            logging.info(f"Bedrock request successful on attempt {attempt + 1}")
            break  # Success!

        except ClientError as e:
            if e.response["Error"]["Code"] == "ThrottlingException":
                consecutive_throttles += 1

                if attempt < max_retries - 1:  # Don't sleep on last attempt
                    # Progressive backoff with circuit breaker logic
                    if consecutive_throttles <= 3:
                        # Normal exponential backoff
                        delay = min(base_delay * (2**attempt), max_delay)
                    else:
                        # Circuit breaker: longer delays for persistent throttling
                        delay = min(base_delay * (3**attempt), max_delay)

                    # Add jitter (20-40% of delay) to prevent thundering herd
                    jitter = delay * (0.2 + random.random() * 0.2)
                    total_delay = delay + jitter

                    # Additional stagger for concurrent instances
                    instance_stagger = (
                        (stagger_seed % 100) / 100 * 2
                    )  # 0-2 second stagger
                    total_delay += instance_stagger

                    logging.warning(
                        f"Bedrock throttled (consecutive: {consecutive_throttles}), "
                        f"retrying in {total_delay:.2f}s (attempt {attempt + 1}/{max_retries})"
                    )

                    time.sleep(total_delay)
                    continue
                else:
                    logging.error(
                        f"Bedrock throttling - max retries ({max_retries}) exceeded after {consecutive_throttles} consecutive throttles"
                    )
                    raise
            else:
                # Non-throttling error, don't retry
                logging.error(
                    f"Bedrock non-throttling error: {e.response['Error']['Code']}"
                )
                raise

        except Exception as e:
            # Non-ClientError, don't retry
            logging.error(f"Bedrock unexpected error: {str(e)}")
            raise

    return response_text


def generate_fallback_analysis(event_data):
    """
    Generate basic analysis when Bedrock is unavailable

    Args:
        event_data: Event data dictionary

    Returns:
        str: Basic JSON analysis
    """
    event_type = event_data.get(
        "eventTypeCode", event_data.get("event_type", "Unknown")
    )
    service = event_data.get("service", "Unknown")
    status = event_data.get("statusCode", event_data.get("status_code", "unknown"))

    # Basic risk assessment based on event type and service
    risk_level = "MEDIUM"
    if "OPERATIONAL_ISSUE" in event_type.upper():
        risk_level = "HIGH"
    elif "SECURITY" in event_type.upper():
        risk_level = "HIGH"
    elif "MAINTENANCE" in event_type.upper() or "LIFECYCLE" in event_type.upper():
        risk_level = "LOW"

    # Basic time sensitivity
    time_sensitivity = "Routine"
    if status == "open" and risk_level == "HIGH":
        time_sensitivity = "Urgent"
    elif "SECURITY" in event_type.upper():
        time_sensitivity = "High Priority"

    fallback_analysis = {
        "critical": risk_level == "HIGH",
        "risk_level": risk_level,
        "time_sensitivity": time_sensitivity,
        "risk_category": (
            "Service Impact" if "OPERATIONAL" in event_type.upper() else "Maintenance"
        ),
        "impact_analysis": f"Basic analysis: {service} {event_type} event with {status} status",
        "required_actions": "Review event details and assess impact on your resources",
        "consequences_if_ignored": "Potential service disruption if not addressed",
        "event_impact_type": (
            "Service" if "OPERATIONAL" in event_type.upper() else "Informational"
        ),
    }

    return f"FALLBACK ANALYSIS (Bedrock unavailable):\n```json\n{json.dumps(fallback_analysis, indent=2)}\n```"


def analyze_event_with_bedrock(bedrock_client, event_data):
    """
    Analyze an AWS Health event using Amazon Bedrock with focus on outage impact
    """
    try:
        # Get event details
        event_type = event_data.get(
            "eventTypeCode", event_data.get("event_type", "Unknown")
        )
        event_category = event_data.get(
            "eventTypeCategory", event_data.get("event_type_category", "Unknown")
        )
        region = event_data.get("region", "Unknown")

        # Format start time if it's a datetime object
        start_time = event_data.get(
            "startTime", event_data.get("start_time", "Unknown")
        )
        if hasattr(start_time, "isoformat"):
            start_time = start_time.isoformat()

        # Use description for analysis
        description = event_data.get("description", "No description available")

        # Prepare prompt for Bedrock

        prompt = f"""
        You are an AWS expert specializing in outage analysis and business continuity. Your task is to analyze this AWS Health event and determine its potential impact on workload availability, system connectivity, and service outages.
        
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
          "risk_level": "critical|high|medium|low",
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
        - Informational: General information with no direct impact

        IMPORTANT INTERPRETATION GUIDELINES:
            1. Pay careful attention to conditional statements (if/then relationships)
            2. For end-of-support notifications, clearly distinguish between:
                - What happens if the customer takes the recommended action
                - What happens if the customer does NOT take the recommended action
            3. Do not conflate these scenarios or suggest negative outcomes will occur even if recommended actions are taken
        """

        # Determine which model we're using and format accordingly
        model_id = BEDROCK_MODEL_ID
        max_tokens = BEDROCK_MAX_TOKENS
        temperature = BEDROCK_TEMPERATURE
        top_p = BEDROCK_TOP_P

        logging.info(f"Sending request to Bedrock model: '{model_id}'")

        if any(
            model in model_id.lower()
            for model in ["claude-3", "claude-sonnet-4", "claude-3-7", "claude-3-5"]
        ):
            # Modern Claude models use the messages format
            payload = {
                "modelId": model_id,
                "contentType": "application/json",
                "accept": "application/json",
                "body": json.dumps(
                    {
                        "anthropic_version": "bedrock-2023-05-31",
                        "max_tokens": max_tokens,
                        "temperature": temperature,
                        "top_p": top_p,
                        "messages": [{"role": "user", "content": prompt}],
                    }
                ),
            }
        else:
            # Claude 2 and other models use the older prompt format
            payload = {
                "modelId": model_id,
                "contentType": "application/json",
                "accept": "application/json",
                "body": json.dumps(
                    {
                        "prompt": f"\n\nHuman: {prompt}\n\nAssistant:",
                        "max_tokens_to_sample": max_tokens,
                        "temperature": temperature,
                        "top_p": top_p,
                    }
                ),
            }

        # Call Bedrock with advanced retry strategy for concurrent processing
        try:
            response_text = invoke_bedrock_with_advanced_retry(
                bedrock_client, payload, model_id
            )
        except Exception as e:
            logging.error(f"Bedrock analysis failed completely: {str(e)}")
            # Fallback to basic analysis without AI
            response_text = generate_fallback_analysis(event_data)

        # Store the full analysis text as a string
        event_data["analysis_text"] = response_text

        # Try to extract JSON from the response
        json_match = re.search(r"```json\s*(.*?)\s*```", response_text, re.DOTALL)
        if json_match:
            json_str = json_match.group(1)
        else:
            json_match = re.search(r"({.*})", response_text, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_str = response_text

        # Parse the JSON
        try:
            analysis = json.loads(json_str)
            # Normalize risk level to ensure consistency
            if "risk_level" in analysis:
                risk_level = analysis["risk_level"].strip().upper()

                # Ensure "critical" is properly recognized and distinguished from "high"
                if risk_level in ["CRITICAL", "SEVERE"]:
                    analysis["risk_level"] = "CRITICAL"
                    # Make sure critical boolean flag is consistent
                    analysis["critical"] = True
                elif risk_level == "HIGH":
                    analysis["risk_level"] = "HIGH"
                elif risk_level in ["MEDIUM", "MODERATE"]:
                    analysis["risk_level"] = "MEDIUM"
                elif risk_level == "LOW":
                    analysis["risk_level"] = "LOW"

                # If critical flag is True but risk_level isn't CRITICAL, fix it
                if (
                    analysis.get("critical", False)
                    and analysis["risk_level"] != "CRITICAL"
                ):
                    analysis["risk_level"] = "CRITICAL"

            # Update event data with analysis
            event_data.update(analysis)

            return event_data
        except json.JSONDecodeError:
            logging.warning(
                f"Failed to parse JSON from response: {response_text[:200]}..."
            )
            # Provide default values if parsing fails
            event_data.update(
                {
                    "critical": False,
                    "risk_level": "LOW",
                    "account_impact": "LOW",
                    "time_sensitivity": "Routine",
                    "risk_category": "Unknown",
                    "required_actions": "Review event details manually",
                    "impact_analysis": "Unable to automatically analyze this event",
                    "consequences_if_ignored": "Unknown",
                    "affected_resources": "Unknown",
                    "event_impact_type": "Informational",
                }
            )
            return event_data

    except Exception as e:
        logging.error(f"Error in Bedrock analysis: {str(e)}")
        logging.error(f"{traceback.format_exc()}")

        # Provide default values if Bedrock analysis fails
        event_data.update(
            {
                "critical": False,
                "risk_level": "LOW",
                "account_impact": "LOW",
                "time_sensitivity": "Routine",
                "risk_category": "Unknown",
                "required_actions": "Review event details manually",
                "impact_analysis": "Unable to automatically analyze this event",
                "consequences_if_ignored": "Unknown",
                "affected_resources": "Unknown",
                "analysis_text": f"Error during analysis: {str(e)}",
                "event_impact_type": "Informational",
            }
        )
        return event_data

    except Exception as e:
        logging.error(
            f"Unexpected error in analyze_event_with_bedrock: {str(e)}"
        )
        logging.error(f"{traceback.format_exc()}")

        # Provide default values if function fails
        event_data.update(
            {
                "critical": False,
                "risk_level": "LOW",
                "account_impact": "LOW",
                "time_sensitivity": "Routine",
                "risk_category": "Unknown",
                "required_actions": "Review event details manually",
                "impact_analysis": "Unable to automatically analyze this event",
                "consequences_if_ignored": "Unknown",
                "affected_resources": "Unknown",
                "analysis_text": f"Error during analysis: {str(e)}",
                "event_impact_type": "Informational",
            }
        )
        return event_data


def categorize_analysis(analysis_text):
    """
    Extract structured data from Bedrock analysis text
    """
    categories = {
        "critical": False,
        "risk_level": "LOW",
        "impact_analysis": "",
        "required_actions": "",
        "time_sensitivity": "Routine",
        "risk_category": "Unknown",
        "consequences_if_ignored": "",
        "event_category": "Low",
        "event_impact_type": "Informational",
    }

    try:
        # If analysis_text is already a dictionary, use it directly
        if isinstance(analysis_text, dict):
            # Update our categories with values from the dictionary
            for key in categories.keys():
                if key in analysis_text:
                    categories[key] = analysis_text[key]

            # Also check for affected_resources
            if "affected_resources" in analysis_text:
                categories["affected_resources"] = analysis_text["affected_resources"]

            return categories

        # If analysis_text is not a string, convert it to string
        if not isinstance(analysis_text, str):
            analysis_text = str(analysis_text)

        # Try to parse as JSON first
        try:
            json_data = json.loads(analysis_text)
            # If successful, update our categories with values from the JSON
            for key in categories.keys():
                if key in json_data:
                    categories[key] = json_data[key]

            # Also check for affected_resources
            if "affected_resources" in json_data:
                categories["affected_resources"] = json_data["affected_resources"]

            return categories
        except json.JSONDecodeError:
            # Not valid JSON, continue with regex parsing
            pass

        # Extract critical status
        critical_match = re.search(
            r"CRITICAL:\s*(?:\[)?([Yy]es|[Nn]o)(?:\])?", analysis_text
        )
        if critical_match:
            categories["critical"] = critical_match.group(1).lower() == "yes"

        # Extract risk level
        risk_match = re.search(
            r"RISK LEVEL:\s*(?:\[)?([Hh]igh|[Mm]edium|[Ll]ow)(?:\])?", analysis_text
        )
        if risk_match:
            categories["risk_level"] = risk_match.group(1).upper()

        # Extract account impact
        impact_match = re.search(
            r"ACCOUNT IMPACT:\s*(?:\[)?([Hh]igh|[Mm]edium|[Ll]ow)(?:\])?", analysis_text
        )
        if impact_match:
            categories["account_impact"] = impact_match.group(1).lower()

        # Extract impact analysis
        impact_analysis_match = re.search(
            r"IMPACT ANALYSIS:(.*?)(?:REQUIRED ACTIONS:|$)", analysis_text, re.DOTALL
        )
        if impact_analysis_match:
            categories["impact_analysis"] = impact_analysis_match.group(1).strip()

        # Extract required actions
        required_actions_match = re.search(
            r"REQUIRED ACTIONS:(.*?)(?:TIME SENSITIVITY:|$)", analysis_text, re.DOTALL
        )
        if required_actions_match:
            categories["required_actions"] = required_actions_match.group(1).strip()

        # Extract time sensitivity
        time_sensitivity_match = re.search(
            r"TIME SENSITIVITY:\s*([Ii]mmediate|[Uu]rgent|[Ss]oon|[Rr]outine)",
            analysis_text,
        )
        if time_sensitivity_match:
            categories["time_sensitivity"] = time_sensitivity_match.group(
                1
            ).capitalize()

        # Extract risk category
        risk_category_match = re.search(
            r"RISK CATEGORY:\s*([Tt]echnical|[Oo]perational|[Ss]ecurity|[Cc]ompliance|[Cc]ost|[Aa]vailability)",
            analysis_text,
        )
        if risk_category_match:
            categories["risk_category"] = risk_category_match.group(1).capitalize()

        # Extract consequences if ignored
        consequences_match = re.search(
            r"CONSEQUENCES IF IGNORED:(.*?)(?:$)", analysis_text, re.DOTALL
        )
        if consequences_match:
            categories["consequences_if_ignored"] = consequences_match.group(1).strip()

        # Extract affected resources
        affected_match = re.search(
            r"AFFECTED RESOURCES:(.*?)(?:$)", analysis_text, re.DOTALL
        )
        if affected_match:
            categories["affected_resources"] = affected_match.group(1).strip()

        # Extract event impact type (new)
        event_impact_match = re.search(
            r"EVENT IMPACT TYPE:\s*(Service Outage|Billing Impact|Security Issue|Performance Degradation|Maintenance|Informational)",
            analysis_text,
        )
        if event_impact_match:
            categories["event_impact_type"] = event_impact_match.group(1)

    except Exception as e:
        logging.error(f"Error categorizing analysis: {str(e)}")

    return categories
