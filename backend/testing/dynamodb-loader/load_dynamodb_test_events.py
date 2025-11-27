#!/usr/bin/env python3
"""
Script to load CSV test data into DynamoDB health events table
Usage: python load_dynamodb_test_events.py [csv_file_path] [table_name]

Default values:
- CSV file: input/chanshih-health-events.csv (in same directory)
- Table name: health-dashboard-57127d3d-events
"""

import csv
import json
import sys
import os
import boto3
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import argparse

# Default configuration values
# TODO: REPLACE WITH A CSV FILE EXPORTED FROM DYNAMODB
DEFAULT_CSV_FILE = "input/chanshih-health-events-2025-07-30.csv"
# TODO: REPLACE WITH THE NAME OF THE DYNAMODB TALBE IN YOUR ACCOUNT
DEFAULT_TABLE_NAME = "health-dashboard-57127d3d-events"


def calculate_ttl_timestamp(last_update_time):
    """Calculate TTL timestamp (6 months from last update time)"""
    try:
        if last_update_time == "N/A" or not last_update_time:
            last_update_dt = datetime.now(timezone.utc)
        else:
            # Parse the ISO format timestamp
            if last_update_time.endswith("Z"):
                last_update_dt = datetime.fromisoformat(
                    last_update_time.replace("Z", "+00:00")
                )
            else:
                last_update_dt = datetime.fromisoformat(last_update_time)

        # Convert to UTC and remove timezone info for consistent storage
        if last_update_dt.tzinfo is not None:
            last_update_dt = last_update_dt.utctimetuple()
            last_update_dt = datetime(*last_update_dt[:6])

        # Calculate TTL: 6 months (180 days) from last update time
        ttl_date = last_update_dt + timedelta(days=180)
        ttl_unix = int(ttl_date.timestamp())

        return ttl_unix

    except Exception as e:
        print(f"Error calculating TTL for {last_update_time}: {str(e)}")
        # Fallback: use current time + 6 months
        fallback_dt = datetime.now(timezone.utc)
        fallback_ttl = int((fallback_dt + timedelta(days=180)).timestamp())
        return fallback_ttl


def generate_simplified_description(service, event_type_code):
    """Generate a simplified/readable event description based on event type rules"""
    if not service or service == "N/A":
        service = "AWS"

    # Convert event type to uppercase for consistent matching
    event_type_upper = event_type_code.upper() if event_type_code else ""

    # Apply mapping rules based on event type
    if "OPERATIONAL_ISSUE" in event_type_upper:
        return f"{service} - Service disruptions or performance problems"
    elif "SECURITY_NOTIFICATION" in event_type_upper:
        return f"{service} - Security-related alerts and warnings"
    elif "PLANNED_LIFECYCLE_EVENT" in event_type_upper:
        return f"{service} - Lifecycle changes requiring action"
    elif any(
        keyword in event_type_upper
        for keyword in [
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
        # Default case for anything else
        return f"{service} - Service-specific events"


def convert_to_dynamodb_format(row):
    """Convert CSV row to DynamoDB item format"""
    # Get current timestamp for metadata
    analysis_timestamp = datetime.now(timezone.utc).isoformat()
    
    # Helper function to clean CSV values (remove extra quotes)
    def clean_value(value, default=""):
        if not value:
            return default
        # Strip whitespace and remove surrounding quotes if present
        cleaned = value.strip()
        if cleaned.startswith('"') and cleaned.endswith('"'):
            cleaned = cleaned[1:-1]
        return cleaned if cleaned else default
    
    # Calculate TTL
    ttl_timestamp = calculate_ttl_timestamp(row.get("lastUpdateTime", ""))
    
    # Generate simplified description
    simplified_description = generate_simplified_description(
        clean_value(row.get("service", ""), "N/A"), 
        clean_value(row.get("eventType", ""), "N/A")
    )
    
    # Create DynamoDB item with cleaned values
    item = {
        "eventArn": clean_value(row.get("eventArn", "")),
        "accountId": clean_value(row.get("accountId", "")),
        "eventType": clean_value(row.get("eventType", ""), "N/A"),
        "eventTypeCategory": clean_value(row.get("eventTypeCategory", ""), "N/A"),
        "region": clean_value(row.get("region", ""), "N/A"),
        "service": clean_value(row.get("service", ""), "N/A"),
        "startTime": clean_value(row.get("startTime", ""), "N/A"),
        "lastUpdateTime": clean_value(row.get("lastUpdateTime", ""), "N/A"),
        "statusCode": clean_value(row.get("statusCode", ""), "unknown"),
        "description": clean_value(row.get("description", ""), "N/A"),
        "simplifiedDescription": simplified_description,
        "critical": clean_value(row.get("critical", ""), "false").lower() == "true",
        "riskLevel": clean_value(row.get("riskLevel", ""), "LOW"),
        "accountName": clean_value(row.get("accountName", ""), "N/A"),
        "timeSensitivity": clean_value(row.get("timeSensitivity", ""), "Routine"),
        "riskCategory": clean_value(row.get("riskCategory", ""), "Unknown"),
        "eventImpactType": clean_value(row.get("eventImpactType", ""), "Informational"),
        "requiredActions": clean_value(row.get("requiredActions", ""), ""),
        "impactAnalysis": clean_value(row.get("impactAnalysis", ""), ""),
        "consequencesIfIgnored": clean_value(row.get("consequencesIfIgnored", ""), ""),
        "affectedResources": clean_value(row.get("affectedResources", ""), "None specified"),
        "analysisTimestamp": analysis_timestamp,
        "analysisVersion": clean_value(row.get("analysisVersion", ""), "1.0"),
        "ttl": ttl_timestamp,
    }
    
    # Convert any empty strings to None (null in DynamoDB)
    # BUT keep "N/A" as a valid string value
    for key, value in item.items():
        if value == "" and key not in ["requiredActions", "impactAnalysis", "consequencesIfIgnored"]:
            item[key] = None
    
    # Handle decimal conversion for numeric values
    item = json.loads(json.dumps(item), parse_float=Decimal)
    
    return item


def load_csv_to_dynamodb(csv_file_path, table_name, batch_size=25):
    """Load CSV data into DynamoDB table"""
    
    # Initialize DynamoDB resource with us-east-1 region
    dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
    table = dynamodb.Table(table_name)
    
    # Counters
    total_rows = 0
    successful_inserts = 0
    failed_inserts = 0
    updated_items = 0
    
    print(f"Loading data from {csv_file_path} into table {table_name}")
    
    try:
        with open(csv_file_path, 'r', encoding='utf-8') as csvfile:
            # Use csv.DictReader to automatically handle headers
            reader = csv.DictReader(csvfile)
            
            batch = []
            
            for row in reader:
                total_rows += 1
                
                try:
                    # Convert row to DynamoDB format
                    item = convert_to_dynamodb_format(row)
                    
                    # Skip if missing required keys
                    if not item.get("eventArn") or not item.get("accountId"):
                        print(f"Skipping row {total_rows}: Missing eventArn or accountId")
                        failed_inserts += 1
                        continue
                    
                    batch.append(item)
                    
                    # Process batch when it reaches batch_size
                    if len(batch) >= batch_size:
                        success, updated = process_batch(table, batch)
                        successful_inserts += success
                        updated_items += updated
                        failed_inserts += (len(batch) - success)
                        batch = []
                        
                        # Progress update
                        if total_rows % 100 == 0:
                            print(f"Processed {total_rows} rows...")
                    
                except Exception as e:
                    print(f"Error processing row {total_rows}: {str(e)}")
                    failed_inserts += 1
                    continue
            
            # Process remaining items in batch
            if batch:
                success, updated = process_batch(table, batch)
                successful_inserts += success
                updated_items += updated
                failed_inserts += (len(batch) - success)
    
    except FileNotFoundError:
        print(f"Error: CSV file not found: {csv_file_path}")
        return False
    except Exception as e:
        print(f"Error reading CSV file: {str(e)}")
        return False
    
    # Print summary
    print(f"\n=== Load Summary ===")
    print(f"Total rows processed: {total_rows}")
    print(f"Successful inserts: {successful_inserts}")
    print(f"Updated items: {updated_items}")
    print(f"Failed inserts: {failed_inserts}")
    
    return failed_inserts == 0


def process_batch(table, batch):
    """Process a batch of items for DynamoDB insertion"""
    successful = 0
    updated = 0
    
    for item in batch:
        try:
            # Check if item already exists
            response = table.get_item(
                Key={
                    "eventArn": item["eventArn"],
                    "accountId": item["accountId"]
                }
            )
            
            if "Item" in response:
                print(f"Updating existing item: {item['eventArn']} for account {item['accountId']}")
                updated += 1
            
            # Insert or update the item
            table.put_item(Item=item)
            successful += 1
            
        except Exception as e:
            print(f"Error inserting item {item.get('eventArn', 'unknown')}: {str(e)}")
            continue
    
    return successful, updated


def main():
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Build full path for default CSV file
    default_csv_file = os.path.join(script_dir, DEFAULT_CSV_FILE)
    default_table_name = DEFAULT_TABLE_NAME
    
    parser = argparse.ArgumentParser(
        description='Load CSV test data into DynamoDB health events table',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Default values:
  CSV file: {default_csv_file}
  Table name: {default_table_name}

Examples:
  python load_dynamodb_test_events.py
  python load_dynamodb_test_events.py my-events.csv
  python load_dynamodb_test_events.py my-events.csv my-table-name
        """
    )
    
    parser.add_argument('csv_file', nargs='?', default=default_csv_file,
                       help=f'Path to the CSV file (default: {os.path.basename(default_csv_file)})')
    parser.add_argument('table_name', nargs='?', default=default_table_name,
                       help=f'DynamoDB table name (default: {default_table_name})')
    parser.add_argument('--batch-size', type=int, default=25, 
                       help='Batch size for processing (default: 25)')
    
    args = parser.parse_args()
    
    # Use provided arguments or defaults
    csv_file_path = args.csv_file
    table_name = args.table_name
    
    print(f"Using CSV file: {csv_file_path}")
    print(f"Using table name: {table_name}")
    print(f"Batch size: {args.batch_size}")
    print()
    
    # Validate CSV file exists
    if not os.path.exists(csv_file_path):
        print(f"Error: CSV file not found: {csv_file_path}")
        sys.exit(1)
    
    # Load data
    success = load_csv_to_dynamodb(csv_file_path, table_name, args.batch_size)
    
    if success:
        print("Data loaded successfully!")
        sys.exit(0)
    else:
        print("Data loading completed with errors")
        sys.exit(1)


if __name__ == "__main__":
    main()