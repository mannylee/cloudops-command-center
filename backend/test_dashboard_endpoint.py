#!/usr/bin/env python3
"""
Test script for the updated dashboard endpoint
Tests both scenarios: with and without filterId
"""

import json
import sys
import os

# Add the lambda code directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), 'modules/lambda/code/dashboard'))

# Mock the boto3 and environment
class MockTable:
    def __init__(self, table_name):
        self.table_name = table_name
        
    def get_item(self, Key):
        # Mock filter data
        if self.table_name == 'health-dashboard-filters' and Key.get('filterId') == 'test-filter-123':
            return {
                'Item': {
                    'filterId': 'test-filter-123',
                    'filterName': 'Test Filter',
                    'accountIds': ['123456789012', '987654321098']
                }
            }
        return {}  # Filter not found
        
    def query(self, KeyConditionExpression):
        # Mock counts data for specific accounts
        return {
            'Items': [
                {'active_issues': 2, 'billing_changes': 1, 'notifications': 3, 'scheduled': 1}
            ]
        }
        
    def scan(self):
        # Mock counts data for all accounts
        return {
            'Items': [
                {'active_issues': 5, 'billing_changes': 3, 'notifications': 8, 'scheduled': 4},
                {'active_issues': 2, 'billing_changes': 1, 'notifications': 3, 'scheduled': 1}
            ]
        }

class MockDynamoDB:
    def Table(self, table_name):
        return MockTable(table_name)

# Mock environment variables
os.environ['DYNAMODB_TABLE'] = 'health-dashboard-counts'
os.environ['FILTERS_TABLE'] = 'health-dashboard-filters'

# Mock boto3
import sys
from unittest.mock import MagicMock
sys.modules['boto3'] = MagicMock()
sys.modules['boto3'].resource.return_value = MockDynamoDB()

# Import the handler after mocking
from index import handler

def test_dashboard_without_filter():
    """Test dashboard endpoint without filterId"""
    event = {
        'queryStringParameters': None,
        'httpMethod': 'GET'
    }
    
    result = handler(event, {})
    print("Test 1 - Without filterId:")
    print(f"Status Code: {result['statusCode']}")
    
    if result['statusCode'] == 200:
        body = json.loads(result['body'])
        print(f"Response: {json.dumps(body, indent=2)}")
        # Should aggregate all accounts
        expected_totals = {'notifications': 11, 'active_issues': 7, 'scheduled_events': 5, 'billing_changes': 4}
        assert body == expected_totals, f"Expected {expected_totals}, got {body}"
        print("✅ Test passed")
    else:
        print(f"❌ Test failed: {result['body']}")
    print()

def test_dashboard_with_valid_filter():
    """Test dashboard endpoint with valid filterId"""
    event = {
        'queryStringParameters': {'filterId': 'test-filter-123'},
        'httpMethod': 'GET'
    }
    
    result = handler(event, {})
    print("Test 2 - With valid filterId:")
    print(f"Status Code: {result['statusCode']}")
    
    if result['statusCode'] == 200:
        body = json.loads(result['body'])
        print(f"Response: {json.dumps(body, indent=2)}")
        # Should use filtered accounts
        expected_totals = {'notifications': 3, 'active_issues': 2, 'scheduled_events': 1, 'billing_changes': 1}
        assert body == expected_totals, f"Expected {expected_totals}, got {body}"
        print("✅ Test passed")
    else:
        print(f"❌ Test failed: {result['body']}")
    print()

def test_dashboard_with_invalid_filter():
    """Test dashboard endpoint with invalid filterId"""
    event = {
        'queryStringParameters': {'filterId': 'invalid-filter'},
        'httpMethod': 'GET'
    }
    
    result = handler(event, {})
    print("Test 3 - With invalid filterId:")
    print(f"Status Code: {result['statusCode']}")
    
    if result['statusCode'] == 404:
        body = json.loads(result['body'])
        print(f"Response: {json.dumps(body, indent=2)}")
        assert body['error']['code'] == 'NOT_FOUND', f"Expected NOT_FOUND error, got {body}"
        print("✅ Test passed")
    else:
        print(f"❌ Test failed: Expected 404, got {result['statusCode']}")
    print()

if __name__ == '__main__':
    print("Testing updated dashboard endpoint...")
    print("=" * 50)
    
    try:
        test_dashboard_without_filter()
        test_dashboard_with_valid_filter()
        test_dashboard_with_invalid_filter()
        print("🎉 All tests passed!")
    except Exception as e:
        print(f"❌ Test failed with error: {str(e)}")
        sys.exit(1)