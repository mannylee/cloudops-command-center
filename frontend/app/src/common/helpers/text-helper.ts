export abstract class TextHelper {
    static truncate(text: string, maxLength: number): string {
        if (text.length <= maxLength) {
            return text;
        }
        return text.substring(0, maxLength) + "...";
    }

    static capitalize(text: string): string {
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    static formatTitle(text: string): string {
        return text
            .split(/[-_\s]+/)
            .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
            .join(" ");
    }

    static formatEventName(eventTypeCode: string): string {
        return eventTypeCode
            .split(/[-_\s]+/)
            .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
            .join(" ");
    }

    static formatTimestamp(timestamp: number | string): string {
        const date = new Date(typeof timestamp === 'number' ? timestamp * 1000 : timestamp);
        return date.toLocaleString();
    }

    static getPriorityText(priority: string): string {
        return priority.charAt(0).toUpperCase() + priority.slice(1).toLowerCase();
    }

    static getTextFilterCounterText(count: number | undefined): string {
        const safeCount = count || 0;
        return safeCount === 1 ? `1 match` : `${safeCount} matches`;
    }

    /**
     * Formats account IDs for display, handling both old array format and new object format
     * @param accountIds - Either string[] (old format) or { [accountId: string]: string } (new format)
     * @returns Formatted string for display
     */
    static formatAccountIds(accountIds: string[] | { [accountId: string]: string } | undefined): string {
        if (!accountIds) return "-";
        
        // Handle old array format for backward compatibility
        if (Array.isArray(accountIds)) {
            return accountIds.join(", ");
        }
        
        // Handle new object format: show "AccountID (AccountName)" or just AccountID if name is same as ID
        return Object.entries(accountIds)
            .map(([accountId, accountName]) => 
                accountName && accountName !== accountId 
                    ? `${accountId} (${accountName})`
                    : accountId
            )
            .join(", ");
    }

    /**
     * Formats account IDs as a list for table display
     * @param accountIds - Either string[] (old format) or { [accountId: string]: string } (new format)
     * @returns Array of formatted account strings for list display
     */
    static formatAccountIdsList(accountIds: string[] | { [accountId: string]: string } | undefined): string[] {
        if (!accountIds) return [];
        
        // Handle old array format for backward compatibility
        if (Array.isArray(accountIds)) {
            return accountIds;
        }
        
        // Handle new object format: show "AccountID (AccountName)" or just AccountID if name is same as ID
        return Object.entries(accountIds)
            .map(([accountId, accountName]) => 
                accountName && accountName !== accountId 
                    ? `${accountId} (${accountName})`
                    : accountId
            );
    }
}