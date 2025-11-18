import { useEffect, useState } from "react";
import { HealthEventItem } from "../../../common/types";
import BaseAppLayout from "../../../components/base-app-layout";
import { BreadcrumbGroup, SpaceBetween, Tabs } from "@cloudscape-design/components";
import { useOnFollow } from "../../../common/hooks/use-on-follow";
import { APP_NAME } from "../../../common/constants";
import { ApiClient } from "../../../common/api-client/api-client";
import { useParams } from "react-router-dom";
import { TextHelper } from "../../../common/helpers/text-helper";
import HealthEventDetailPageHeader from "./health-event-detail-header";
import HealthEventDetailDetailBox from "./health-event-detail-detail-box";
import HealthEventDetailAiSuggestion from "./health-event-detail-ai-suggestion";
import HealthEventDetailDetailTab from "./health-event-detail-detail-tab";
import HealthEventDetailEntityTab from "./health-event-detail-detail-entity-tab";
import { useHealth } from "../../../context/health-context";

const initialHealthData: HealthEventItem = {
  arn: "",
  details: "",
  endTime: "0",
  entities: [],
  eventScopeCode: "",
  eventTypeCategory: "",
  eventTypeCode: "",
  lastUpdatedTime: 0,
  priority: "",
  region: "",
  service: "",
  startTime: 0,
  statusCode: "",
  reasons: [],
  impact: [],
  resolution: [],
  cloudProvider: "",
};

export default function HealthEventDetailPage() {
  const onFollow = useOnFollow();
  const { arn } = useParams();
  const [loading, setLoading] = useState(true);
  const [priorityText, setPriorityText] = useState<string>("");
  const [eventData, setEventData] = useState<HealthEventItem>(initialHealthData);
  const { getEventDetail, setEventDetail } = useHealth();

  async function getSingleHealthEvent(arn: string) {
    try {
      // Check if we already have this event in context
      const cachedEvent = getEventDetail(arn);
      
      if (cachedEvent) {
        // Use cached data
        setEventData(cachedEvent);
        const priorityText = TextHelper.getPriorityText(cachedEvent.priority);
        setPriorityText(priorityText);
      } else {
        // Fetch from API
        const apiClient = new ApiClient();
        const fetchedEvent = await apiClient.health.getSingleHealthEvent(arn);
        
        // Update local state
        setEventData(fetchedEvent);
        
        // Store in context
        setEventDetail(arn, fetchedEvent);
        
        const priorityText = TextHelper.getPriorityText(fetchedEvent.priority);
        setPriorityText(priorityText);
      }
    } catch (error) {
      console.error(`Error fetching health event details for ARN ${arn}:`, error);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (arn) {
      getSingleHealthEvent(arn);
    }
  }, [arn]);

  return (
    <BaseAppLayout
      breadcrumbs={
        <BreadcrumbGroup
          onFollow={onFollow}
          items={[
            {
              text: APP_NAME,
              href: "/",
            },
            {
              text: "Health",
              href: "/",
            },
            {
              text: priorityText ? priorityText : "Category",
              href: `/health/category/${eventData?.priority}`,
            },
            {
              text: "Health Event",
              href: "#",
            },
          ]}
        />
      }
      content={
        <SpaceBetween size="m">
          <HealthEventDetailPageHeader eventName={`${TextHelper.formatEventName(eventData.eventTypeCode)}`} />
          <HealthEventDetailDetailBox event={eventData!} loading={loading} />
          <HealthEventDetailAiSuggestion event={eventData!} loading={loading} />
          <Tabs
            tabs={[
              {
                label: "Details",
                id: "detailTab",
                content: <HealthEventDetailDetailTab eventDetail={eventData.details} />,
              },
              {
                label: "Effected Entity",
                id: "entityTab",
                content: <HealthEventDetailEntityTab entities={eventData.entities} />,
              },
            ]}
          />
        </SpaceBetween>
      }
    />
  );
}
