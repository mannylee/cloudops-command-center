import json
import os
import uuid
import boto3
import logging
from botocore.exceptions import ClientError

# Set up logging for Lambda
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

dynamodb = boto3.resource("dynamodb")
table_name = os.environ.get("DYNAMODB_TABLE", "health-dashboard-filters")
table = dynamodb.Table(table_name)

# Standard CORS headers
CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "authorization,content-type,x-requested-with,x-amz-date,x-amz-security-token,x-api-key",
}


def handler(event, context):
    """
    Lambda function for filters management
    Handles CRUD operations for filters
    """

    try:
        # Log incoming event
        logger.info(
            f"Filters API handler invoked with event: {json.dumps(event, default=str)}"
        )

        http_method = event.get("httpMethod", "")
        path = event.get("path", "")
        path_params = event.get("pathParameters") or {}

        logger.debug(f"Received {http_method} request for path: {path}")

        # Handle CORS preflight OPTIONS request
        if http_method == "OPTIONS":
            logger.debug("Handling OPTIONS request")
            return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

        if http_method == "GET" and not path_params.get("filterId"):
            # GET /filters
            logger.info("Retrieving all filters")
            return get_all_filters()
        elif http_method == "GET" and path_params.get("filterId"):
            # GET /filters/{filterId}
            filter_id = path_params["filterId"]
            logger.info(f"Retrieving filter: {filter_id}")
            return get_filter(filter_id)
        elif http_method == "POST":
            # POST /filters
            body = json.loads(event.get("body", "{}"))
            logger.info(f"Creating new filter: {body.get('filterName', 'unnamed')}")
            return create_filter(body)
        elif http_method == "PUT":
            # PUT /filters/{filterId}
            body = json.loads(event.get("body", "{}"))
            filter_id = path_params["filterId"]
            logger.info(f"Updating filter: {filter_id}")
            return update_filter(filter_id, body)
        elif http_method == "DELETE":
            # DELETE /filters/{filterId}
            filter_id = path_params["filterId"]
            logger.info(f"Deleting filter: {filter_id}")
            return delete_filter(filter_id)
        else:
            logger.warning(f"Method not allowed: {http_method} for path: {path}")
            return {
                "statusCode": 405,
                "headers": CORS_HEADERS,
                "body": json.dumps(
                    {
                        "error": {
                            "code": "METHOD_NOT_ALLOWED",
                            "message": "Method not allowed",
                        }
                    }
                ),
            }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "INTERNAL_ERROR",
                        "message": "An internal server error occurred",
                    }
                }
            ),
        }


def get_all_filters():
    """Get all filters"""
    try:
        logger.debug("Scanning filters table for all filters")
        response = table.scan()
        filters = []

        for item in response.get("Items", []):
            filters.append(
                {
                    "filterId": item["filterId"],
                    "filterName": item["filterName"],
                    "description": item.get("description", ""),
                    "accountIds": item.get("accountIds", []),
                }
            )

        logger.info(f"Retrieved {len(filters)} filters")
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": json.dumps(filters)}
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "DATABASE_ERROR",
                        "message": "Failed to retrieve filters",
                    }
                }
            ),
        }


def get_filter(filter_id):
    """Get specific filter"""
    try:
        logger.debug(f"Looking up filter: {filter_id}")
        response = table.get_item(Key={"filterId": filter_id})

        if "Item" not in response:
            logger.warning(f"Filter not found: {filter_id}")
            return {
                "statusCode": 404,
                "headers": CORS_HEADERS,
                "body": json.dumps(
                    {"error": {"code": "NOT_FOUND", "message": "Filter not found"}}
                ),
            }

        item = response["Item"]
        filter_data = {
            "filterId": item["filterId"],
            "filterName": item["filterName"],
            "description": item.get("description", ""),
            "accountIds": item.get("accountIds", []),
        }

        logger.debug(
            f"Found filter '{item['filterName']}' with {len(item.get('accountIds', []))} accounts"
        )
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps(filter_data),
        }
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "DATABASE_ERROR",
                        "message": "Failed to retrieve filter",
                    }
                }
            ),
        }


def create_filter(data):
    """Create new filter"""
    logger.debug(f"Validating filter data: {data.get('filterName', 'unnamed')}")

    # Validate required fields
    if not data.get("filterName"):
        logger.warning("Filter creation failed: filterName is required")
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "VALIDATION_ERROR",
                        "message": "filterName is required",
                    }
                }
            ),
        }

    if not data.get("accountIds"):
        logger.warning("Filter creation failed: accountIds is required")
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "VALIDATION_ERROR",
                        "message": "accountIds is required",
                    }
                }
            ),
        }

    try:
        filter_id = str(uuid.uuid4())

        item = {
            "filterId": filter_id,
            "filterName": data["filterName"],
            "description": data.get("description", ""),
            "accountIds": data["accountIds"],
        }

        logger.debug(
            f"Creating filter '{data['filterName']}' with {len(data['accountIds'])} accounts"
        )
        table.put_item(Item=item)

        logger.info(
            f"Successfully created filter '{data['filterName']}' with ID: {filter_id}"
        )
        return {"statusCode": 201, "headers": CORS_HEADERS, "body": json.dumps(item)}
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "DATABASE_ERROR",
                        "message": "Failed to create filter",
                    }
                }
            ),
        }


def update_filter(filter_id, data):
    """Update existing filter"""
    try:
        logger.debug(f"Checking if filter exists: {filter_id}")
        # Check if filter exists
        response = table.get_item(Key={"filterId": filter_id})
        if "Item" not in response:
            logger.warning(f"Update failed: filter not found: {filter_id}")
            return {
                "statusCode": 404,
                "headers": CORS_HEADERS,
                "body": json.dumps(
                    {"error": {"code": "NOT_FOUND", "message": "Filter not found"}}
                ),
            }

        # Build update expression
        update_expression = "SET "
        expression_values = {}
        expression_names = {}
        updated_fields = []

        if "filterName" in data:
            update_expression += "#fn = :fn, "
            expression_names["#fn"] = "filterName"
            expression_values[":fn"] = data["filterName"]
            updated_fields.append("filterName")

        if "description" in data:
            update_expression += "#desc = :desc, "
            expression_names["#desc"] = "description"
            expression_values[":desc"] = data["description"]
            updated_fields.append("description")

        if "accountIds" in data:
            update_expression += "accountIds = :aids, "
            expression_values[":aids"] = data["accountIds"]
            updated_fields.append(f"accountIds ({len(data['accountIds'])} accounts)")

        # Remove trailing comma and space
        update_expression = update_expression.rstrip(", ")

        if not expression_values:
            logger.warning(
                f"Update failed: no valid fields to update for filter {filter_id}"
            )
            return {
                "statusCode": 400,
                "headers": CORS_HEADERS,
                "body": json.dumps(
                    {
                        "error": {
                            "code": "VALIDATION_ERROR",
                            "message": "No valid fields to update",
                        }
                    }
                ),
            }

        logger.debug(f"Updating fields: {', '.join(updated_fields)}")

        # Update the item
        update_params = {
            "Key": {"filterId": filter_id},
            "UpdateExpression": update_expression,
            "ExpressionAttributeValues": expression_values,
            "ReturnValues": "ALL_NEW",
        }

        if expression_names:
            update_params["ExpressionAttributeNames"] = expression_names

        response = table.update_item(**update_params)

        updated_item = {
            "filterId": response["Attributes"]["filterId"],
            "filterName": response["Attributes"]["filterName"],
            "description": response["Attributes"].get("description", ""),
            "accountIds": response["Attributes"].get("accountIds", []),
        }

        logger.info(
            f"Successfully updated filter '{updated_item['filterName']}' (ID: {filter_id})"
        )
        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps(updated_item),
        }
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "DATABASE_ERROR",
                        "message": "Failed to update filter",
                    }
                }
            ),
        }


def delete_filter(filter_id):
    """Delete filter"""
    try:
        logger.debug(f"Checking if filter exists before deletion: {filter_id}")
        # Check if filter exists
        response = table.get_item(Key={"filterId": filter_id})
        if "Item" not in response:
            logger.warning(f"Delete failed: filter not found: {filter_id}")
            return {
                "statusCode": 404,
                "headers": CORS_HEADERS,
                "body": json.dumps(
                    {"error": {"code": "NOT_FOUND", "message": "Filter not found"}}
                ),
            }

        filter_name = response["Item"].get("filterName", "unnamed")

        # Delete the item
        table.delete_item(Key={"filterId": filter_id})

        logger.info(f"Successfully deleted filter '{filter_name}' (ID: {filter_id})")
        return {"statusCode": 204, "headers": CORS_HEADERS, "body": ""}
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps(
                {
                    "error": {
                        "code": "DATABASE_ERROR",
                        "message": "Failed to delete filter",
                    }
                }
            ),
        }
