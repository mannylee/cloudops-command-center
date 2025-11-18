/**
 * Formats a date string or timestamp into a user-friendly format
 * @param dateString - ISO date string or timestamp
 * @returns Formatted date string or "N/A" if invalid
 */
export function formatLastUpdateTime(dateString: string | undefined | null): string {
    if (!dateString) {
        return "N/A";
    }

    try {
        const date = new Date(dateString);

        // Check if date is valid
        if (isNaN(date.getTime())) {
            return "N/A";
        }

        const now = new Date();
        const diffInMs = now.getTime() - date.getTime();
        const diffInMinutes = Math.floor(diffInMs / (1000 * 60));
        const diffInHours = Math.floor(diffInMs / (1000 * 60 * 60));
        const diffInDays = Math.floor(diffInMs / (1000 * 60 * 60 * 24));

        // Show relative time for recent events
        if (diffInMinutes < 1) {
            return "Just now";
        } else if (diffInMinutes < 60) {
            return `${diffInMinutes} minute${diffInMinutes === 1 ? '' : 's'} ago`;
        } else if (diffInHours < 24) {
            return `${diffInHours} hour${diffInHours === 1 ? '' : 's'} ago`;
        } else if (diffInDays < 7) {
            return `${diffInDays} day${diffInDays === 1 ? '' : 's'} ago`;
        }

        // For older events, show formatted date
        const options: Intl.DateTimeFormatOptions = {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            hour12: true
        };

        return date.toLocaleDateString('en-US', options);
    } catch (error) {
        console.error('Error formatting date:', error);
        return "N/A";
    }
}

/**
 * Formats a date string into a detailed format for event details page
 * @param dateString - ISO date string or timestamp
 * @returns Detailed formatted date string or "N/A" if invalid
 */
export function formatDetailedDateTime(dateString: string | undefined | null): string {
    if (!dateString) {
        return "N/A";
    }

    try {
        const date = new Date(dateString);

        // Check if date is valid
        if (isNaN(date.getTime())) {
            return "N/A";
        }

        const options: Intl.DateTimeFormatOptions = {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: true,
            timeZoneName: 'short'
        };

        return date.toLocaleDateString('en-US', options);
    } catch (error) {
        console.error('Error formatting detailed date:', error);
        return "N/A";
    }
}