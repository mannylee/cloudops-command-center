import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useOrgHealth } from "../../../context/org-health-context";
import Container from "@cloudscape-design/components/container";
import Header from "@cloudscape-design/components/header";
import SpaceBetween from "@cloudscape-design/components/space-between";
import Button from "@cloudscape-design/components/button";
import ColumnLayout from "@cloudscape-design/components/column-layout";
import Box from "@cloudscape-design/components/box";
import Badge from "@cloudscape-design/components/badge";
import { OrgHealthEvent } from "../../../common/types";
import BaseAppLayout from "../../../components/base-app-layout";
import { BreadcrumbGroup } from "@cloudscape-design/components";
import { useOnFollow } from "../../../common/hooks/use-on-follow";
import { APP_NAME } from "../../../common/constants";
import { formatDetailedDateTime } from "../../../common/helpers/date-helper";

export default function EventDetailPage() {
  const onFollow = useOnFollow();
  const { eventArn } = useParams<{ eventArn: string }>();
  const navigate = useNavigate();
  const { getEventByArn, loading: contextLoading } = useOrgHealth();
  const [event, setEvent] = useState<OrgHealthEvent | null>(null);

  useEffect(() => {
    if (eventArn) {
      const foundEvent = getEventByArn(eventArn);
      setEvent(foundEvent || null);
    }
  }, [eventArn, getEventByArn]);

  if (contextLoading) {
    return <div>Loading...</div>;
  }

  if (!event) {
    return (
      <Container>
        <Header variant="h1" actions={<Button onClick={() => navigate(-1)}>Back</Button>}>
          Event not found
        </Header>
        <Box>The requested event could not be found.</Box>
      </Container>
    );
  }

  const getRiskLevelBadge = (riskLevel: string | undefined) => {
    const level = riskLevel?.toLowerCase() || "medium";

    switch (level) {
      case "critical":
        return <Badge color="severity-critical">Critical</Badge>;
      case "high":
        return <Badge color="severity-high">High</Badge>;
      case "medium":
        return <Badge color="severity-medium">Medium</Badge>;
      case "low":
        return <Badge color="severity-low">Low</Badge>;
      default:
        return <Badge color="severity-medium">Medium</Badge>;
    }
  };

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
              text: "AWS Health Dashboard",
              href: "/",
            },
            {
              text: "Event Details",
              href: "#",
            },
          ]}
        />
      }
      content={
        <Container>
          <SpaceBetween size="l">
            <Header variant="h1" actions={<Button onClick={() => navigate(-1)}>Back</Button>}>
              {event.eventType || event.service || "Event Details"}
            </Header>

            <ColumnLayout columns={2} variant="text-grid">
              <SpaceBetween size="l">
                <div>
                  <Box variant="awsui-key-label">Event ARN</Box>
                  <div>{event.eventArn || "N/A"}</div>
                </div>

                <div>
                  <Box variant="awsui-key-label">Service</Box>
                  <div>{event.service || "N/A"}</div>
                </div>

                <div>
                  <Box variant="awsui-key-label">Region</Box>
                  <div>{event.region || "N/A"}</div>
                </div>
              </SpaceBetween>

              <SpaceBetween size="l">
                <div>
                  <Box variant="awsui-key-label">Risk Level</Box>
                  <div>{getRiskLevelBadge(event.riskLevel)}</div>
                </div>

                <div>
                  <Box variant="awsui-key-label">Last Updated</Box>
                  <div>{formatDetailedDateTime(event.lastUpdateTime)}</div>
                </div>

                <div>
                  <Box variant="awsui-key-label">Risk Category</Box>
                  <div>{event.riskCategory || "N/A"}</div>
                </div>
              </SpaceBetween>
            </ColumnLayout>

            <Container header={<Header variant="h2">Description</Header>}>
              <Box>
                {event.description ? (
                  <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit', margin: 0 }}>
                    {event.description}
                  </pre>
                ) : (
                  "No information available"
                )}
              </Box>
            </Container>

            <Container header={
              <Header variant="h2">
                Consequences If Ignored
                <span 
                  style={{ 
                    marginLeft: '8px', 
                    borderRadius: '16px', 
                    backgroundColor: '#e6f3ff',
                    color: '#219ed3ff',
                    fontSize: '0.8em',
                    padding: '4px 8px',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                >
                  🤖 AI Generated
                </span>
              </Header>
            }>
              <p>{event.consequencesIfIgnored || "No information available"}</p>
            </Container>

            <Container header={
              <Header variant="h2">
                Required Actions
                <span 
                  style={{ 
                    marginLeft: '8px', 
                    borderRadius: '16px', 
                    backgroundColor: '#e6f3ff',
                    color: '#219ed3ff',
                    fontSize: '0.8em',
                    padding: '4px 8px',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                >
                  🤖 AI Generated
                </span>
              </Header>
            }>
              <p>{event.requiredActions || "No actions required"}</p>
            </Container>

            <Container header={
              <Header variant="h2">
                Impact Analysis
                <span 
                  style={{ 
                    marginLeft: '8px', 
                    borderRadius: '16px', 
                    backgroundColor: '#e6f3ff',
                    color: '#219ed3ff',
                    fontSize: '0.8em',
                    padding: '4px 8px',
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                >
                  🤖 AI Generated
                </span>
              </Header>
            }>
              <p>{event.impactAnalysis || "No impact analysis available"}</p>
            </Container>

            <Container header={<Header variant="h2">Affected Resources</Header>}>
              <p>{event.affectedResources || "No specific resources affected"}</p>
            </Container>

            <Container header={<Header variant="h2">Affected Accounts</Header>}>
              {event.accountIds && Object.keys(event.accountIds).length > 0 ? (
                <ul>
                  {Object.entries(event.accountIds).map(([accountId, accountName], index) => (
                    <li key={index}>
                      {accountName && accountName !== accountId 
                        ? `${accountId} (${accountName})`
                        : accountId
                      }
                    </li>
                  ))}
                </ul>
              ) : (
                <p>No specific accounts affected</p>
              )}
            </Container>
          </SpaceBetween>
        </Container>
      }
    />
  );
}
