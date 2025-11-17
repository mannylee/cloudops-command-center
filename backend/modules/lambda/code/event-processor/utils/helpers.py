from datetime import datetime

def format_time(time_str):
    """
    Format time string to be consistent
    
    Args:
        time_str (str): ISO format time string
        
    Returns:
        str: Formatted time string (YYYY-MM-DD)
    """
    if not time_str or time_str == 'N/A':
        return 'N/A'
    
    try:
        # If it's already a datetime object
        if isinstance(time_str, datetime):
            return time_str.strftime('%Y-%m-%d')
        
        # Parse ISO format
        dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d')
    except Exception:
        # If we can't parse it, return as is
        return time_str

def extract_affected_resources(entities):
    """
    Extract affected resources from Health API entities
    
    Args:
        entities (list): List of entity objects from Health API
        
    Returns:
        str: Comma-separated list of affected resources
    """
    if not entities:
        return "None specified"
    
    resources = []
    for entity in entities:
        entity_value = entity.get('entityValue', '')
        if entity_value:
            resources.append(entity_value)
    
    if resources:
        return ", ".join(resources)
    else:
        return "None specified"

def get_account_id_from_event(event_arn):
    """
    Extract account ID from event ARN if possible
    
    Args:
        event_arn (str): ARN of the health event
        
    Returns:
        str: Account ID or empty string
    """
    try:
        # ARN format: arn:aws:health:region::event/service/id/account-id
        parts = event_arn.split('/')
        if len(parts) >= 4:
            return parts[3]
        return ""
    except Exception:
        return ""