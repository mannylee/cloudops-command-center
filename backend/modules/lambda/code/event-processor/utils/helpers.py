from datetime import datetime

def format_date_only(time_str):
    """
    Format time string to date only (YYYY-MM-DD)
    Used for startTime field
    
    Args:
        time_str (str): ISO format or RFC 2822 format time string
        
    Returns:
        str: Date string (YYYY-MM-DD)
    """
    if not time_str or time_str == 'N/A':
        return 'N/A'
    
    try:
        # If it's already a datetime object
        if isinstance(time_str, datetime):
            return time_str.strftime('%Y-%m-%d')
        
        # Try RFC 2822 format first (e.g., "Mon, 15 Dec 2025 07:00:00 GMT")
        if "GMT" in time_str or "," in time_str:
            from email.utils import parsedate_to_datetime
            dt = parsedate_to_datetime(time_str)
            # Convert to UTC and make naive
            if dt.tzinfo is not None:
                dt = dt.replace(tzinfo=None)
            return dt.strftime('%Y-%m-%d')
        
        # Parse ISO format
        dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d')
    except Exception:
        # If we can't parse it, return as is
        return time_str


def format_datetime(time_str):
    """
    Format time string to datetime (YYYY-MM-DD HH:MM:SS)
    Used for lastUpdateTime field
    
    Args:
        time_str (str): ISO format or RFC 2822 format time string
        
    Returns:
        str: Datetime string (YYYY-MM-DD HH:MM:SS)
    """
    if not time_str or time_str == 'N/A':
        return 'N/A'
    
    try:
        # If it's already a datetime object
        if isinstance(time_str, datetime):
            return time_str.strftime('%Y-%m-%d %H:%M:%S')
        
        # Try RFC 2822 format first (e.g., "Mon, 15 Dec 2025 07:00:00 GMT")
        if "GMT" in time_str or "," in time_str:
            from email.utils import parsedate_to_datetime
            dt = parsedate_to_datetime(time_str)
            # Convert to UTC and make naive
            if dt.tzinfo is not None:
                dt = dt.replace(tzinfo=None)
            return dt.strftime('%Y-%m-%d %H:%M:%S')
        
        # Parse ISO format
        dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
        # Make naive (remove timezone) for consistent storage
        if dt.tzinfo is not None:
            dt = dt.replace(tzinfo=None)
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        # If we can't parse it, return as is
        return time_str


def format_time(time_str):
    """
    Legacy function for backward compatibility
    Defaults to date-only format
    
    Args:
        time_str (str): ISO format or RFC 2822 format time string
        
    Returns:
        str: Date string (YYYY-MM-DD)
    """
    return format_date_only(time_str)

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