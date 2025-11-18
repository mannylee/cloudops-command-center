import { createContext, useContext, useState, useEffect, ReactNode } from "react";
import { ApiClient } from "../common/api-client/api-client";
import { OrgHealthEvent, OrgHealthFilter } from "../common/types";

interface OrgHealthSummary {
  notifications: number;
  active_issues: number;
  scheduled_events: number;
  billing_changes: number;
}

interface OrgHealthContextType {
  events: OrgHealthEvent[];
  loading: boolean;
  summary: OrgHealthSummary;
  filters: OrgHealthFilter[];
  selectedFilter: OrgHealthFilter | null;
  categoryFilter: string | null;
  refreshEvents: () => Promise<void>;
  getEventByArn: (eventArn: string) => OrgHealthEvent | undefined;
  setSummary: (summary: OrgHealthSummary) => void;
  setFilters: (filters: OrgHealthFilter[]) => void;
  setSelectedFilter: (filter: OrgHealthFilter | null) => void;
  setCategoryFilter: (category: string | null) => void;
  filteredEvents: OrgHealthEvent[];
}

const OrgHealthContext = createContext<OrgHealthContextType | undefined>(undefined);

export function OrgHealthProvider({ children }: { children: ReactNode }) {
  const [events, setEvents] = useState<OrgHealthEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState<OrgHealthFilter[]>([]);
  const [selectedFilter, setSelectedFilter] = useState<OrgHealthFilter | null>(null);
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const [summary, setSummary] = useState<OrgHealthSummary>({
    notifications: 0,
    active_issues: 0,
    scheduled_events: 0,
    billing_changes: 0,
  });

  const fetchEvents = async () => {
    try {
      setLoading(true);
      const apiClient = new ApiClient();
      const filterId = selectedFilter?.filterId;

      // Fetch all types of events in parallel with the selected filter
      const [billingEvents, issuesEvents, notificationsEvents, scheduledEvents] = await Promise.all([
        apiClient.orgHealth.getOrgHealthBillingEvents(filterId),
        apiClient.orgHealth.getOrgHealthIssuesEvents(filterId),
        apiClient.orgHealth.getOrgHealthNotificationsEvents(filterId),
        apiClient.orgHealth.getOrgHealthScheduledEvents(filterId),
      ]);

      // Add eventCategory to each event based on its source API method
      const billingEventsWithCategory = Array.isArray(billingEvents) 
        ? billingEvents.map(event => ({ ...event, eventCategory: "Billing" }))
        : [];
        
      const issuesEventsWithCategory = Array.isArray(issuesEvents)
        ? issuesEvents.map(event => ({ ...event, eventCategory: "Issue" }))
        : [];
        
      const notificationsEventsWithCategory = Array.isArray(notificationsEvents)
        ? notificationsEvents.map(event => ({ ...event, eventCategory: "Notification" }))
        : [];
        
      const scheduledEventsWithCategory = Array.isArray(scheduledEvents)
        ? scheduledEvents.map(event => ({ ...event, eventCategory: "Scheduled" }))
        : [];

      // Combine the events with their categories
      const combinedEvents = [
        ...billingEventsWithCategory,
        ...issuesEventsWithCategory,
        ...notificationsEventsWithCategory,
        ...scheduledEventsWithCategory,
      ];

      setEvents(combinedEvents);
    } catch (error) {
      console.error("Error fetching events:", error);
      setEvents([]);
    } finally {
      setLoading(false);
    }
  };

  // Function to get an event by ARN
  const getEventByArn = (eventArn: string): OrgHealthEvent | undefined => {
    return events.find((event) => event.eventArn === eventArn);
  };

  // Initial fetch
  useEffect(() => {
    fetchEvents();
  }, []);
  
  // Refresh events when selected filter changes
  useEffect(() => {
    fetchEvents();
  }, [selectedFilter]);

  // Filter events based on category filter
  const filteredEvents = categoryFilter
    ? events.filter(event => event.eventCategory === categoryFilter)
    : events;

  return (
    <OrgHealthContext.Provider
      value={{
        events,
        loading,
        summary,
        filters,
        selectedFilter,
        categoryFilter,
        refreshEvents: fetchEvents,
        getEventByArn,
        setSummary,
        setFilters,
        setSelectedFilter,
        setCategoryFilter,
        filteredEvents,
      }}
    >
      {children}
    </OrgHealthContext.Provider>
  );
}

export function useOrgHealth() {
  const context = useContext(OrgHealthContext);
  if (context === undefined) {
    throw new Error("useOrgHealth must be used within an OrgHealthProvider");
  }
  return context;
}
