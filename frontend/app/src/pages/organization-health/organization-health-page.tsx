import { useEffect, useState } from "react";
import {
  Box,
  BreadcrumbGroup,
  Container,
  ContentLayout,
  Grid,
  Header,
  Select,
  SpaceBetween,
  Spinner,
} from "@cloudscape-design/components";
import { useOnFollow } from "../../common/hooks/use-on-follow";
import BaseAppLayout from "../../components/base-app-layout";
import { APP_NAME } from "../../common/constants";
import "./organization-health-page.css";
import OrgHealthAccountNotificationTable from "./account-notification-table";
import RouterButton from "../../components/wrappers/router-button";
import { ApiClient } from "../../common/api-client/api-client";
import { useOrgHealth } from "../../context/org-health-context";
import { OrgHealthFilter } from "../../common/types";
import HealthDashboardInfo from "./components/health-dashboard-info";

export default function OrganizationHealthDashboardPage() {
  const onFollow = useOnFollow();
  const [isInfoPanelOpen, setIsInfoPanelOpen] = useState(false);
  const {
    loading,
    summary,
    setSummary,
    filters,
    setFilters,
    selectedFilter,
    setSelectedFilter,
    setCategoryFilter,
    categoryFilter,
  } = useOrgHealth();

  useEffect(() => {
    fetchData();
    fetchFilters();
  }, []);

  // Refresh summary data when filter selection changes
  useEffect(() => {
    fetchData();
  }, [selectedFilter]);

  async function fetchData() {
    try {
      const apiClient = new ApiClient();
      const filterId = selectedFilter?.filterId;
      const orgHealthSummary = await apiClient.orgHealth.getOrgHealthSummary(filterId);
      setSummary(orgHealthSummary);
    } catch (error) {
      console.error("Error fetching getOrgHealthSummary:", error);
    }
  }

  async function fetchFilters() {
    try {
      const apiClient = new ApiClient();
      const orgHealthFilters = await apiClient.orgHealth.getOrgHealthFilter();
      setFilters(orgHealthFilters);
    } catch (error) {
      console.error("Error fetching getOrgHealthFilter:", error);
    }
  }

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
              text: "Health Event Intelligence",
              href: "#",
            },
          ]}
        />
      }
      content={
        <ContentLayout
          header={
            <Header
              variant="h2"
              actions={
                <SpaceBetween direction="horizontal" size="xs">
                  <Select
                    selectedOption={
                      selectedFilter
                        ? {
                          label: selectedFilter.filterName,
                          value: selectedFilter.filterId,
                          description: selectedFilter.description,
                        }
                        : null
                    }
                    onChange={({ detail }) => {
                      const filterId = detail.selectedOption?.value;
                      const filter = filterId ? filters.find((f: OrgHealthFilter) => f.filterId === filterId) || null : null;
                      setSelectedFilter(filter);
                      // The useEffect hooks will handle refreshing the data automatically
                    }}
                    options={[
                      { label: "No filter", value: "" },
                      ...filters.map((filter: OrgHealthFilter) => ({
                        label: filter.filterName,
                        value: filter.filterId,
                        description: filter.description,
                      })),
                    ]}
                    placeholder="Select a filter"
                    empty="No filters available"
                  />
                  <RouterButton
                    iconAlign="left"
                    iconName="settings"
                    variant="primary"
                    href="/organization-health-dashboard/filter"
                  >
                    Manage Filters
                  </RouterButton>
                </SpaceBetween>
              }
            >
              🏩 Health Event Intelligence
            </Header>
          }
        >
          <SpaceBetween size="l">
            <Grid
              gridDefinition={[
                { colspan: { l: 3, m: 3, default: 12 } },
                { colspan: { l: 3, m: 3, default: 12 } },
                { colspan: { l: 3, m: 3, default: 12 } },
                { colspan: { l: 3, m: 3, default: 12 } },
              ]}
            >
              <Container
                disableHeaderPaddings={true}
                disableContentPaddings={true}
                data-type="notification"
                className={`category-container ${categoryFilter === "Notification" ? "selected" : ""}`}
              >
                <Box textAlign="center" margin={"l"}>
                  <h3>📝 Notification</h3>
                  {loading ? (
                    <Box margin="m">
                      <Spinner size="normal" />
                    </Box>
                  ) : (
                    <>
                      <h1
                        onClick={() => setCategoryFilter("Notification")}
                        style={{ cursor: "pointer", color: "#0073bb" }}
                      >
                        {summary.notifications}
                      </h1>
                      {summary.notifications === 0
                        ? "No notifications"
                        : summary.notifications === 1
                          ? "Requires Attention"
                          : "Require Attention"}
                    </>
                  )}
                </Box>
              </Container>
              <Container
                disableHeaderPaddings={true}
                disableContentPaddings={true}
                data-type="activeIssue"
                className={`category-container ${categoryFilter === "Issue" ? "selected" : ""} ${summary.active_issues === 0 ? "no-issues" : ""
                  }`}
              >
                <Box textAlign="center" margin={"l"}>
                  <h3>🚨 Active Issues</h3>
                  {loading ? (
                    <Box margin="m">
                      <Spinner size="normal" />
                    </Box>
                  ) : (
                    <>
                      <h1
                        onClick={() => setCategoryFilter("Issue")}
                        style={{
                          cursor: "pointer",
                          color: summary.active_issues === 0 ? "#16a34a" : "#d91515"
                        }}
                      >
                        {summary.active_issues}
                      </h1>
                      {summary.active_issues === 0
                        ? "All Resolved"
                        : summary.active_issues === 1
                          ? "Active Issue"
                          : "Active Issues"}
                    </>
                  )}
                </Box>
              </Container>
              <Container
                disableHeaderPaddings={true}
                disableContentPaddings={true}
                data-type="schedule"
                className={`category-container ${categoryFilter === "Scheduled" ? "selected" : ""}`}
              >
                <Box textAlign="center" margin={"l"}>
                  <h3>🗓️ Scheduled</h3>
                  {loading ? (
                    <Box margin="m">
                      <Spinner size="normal" />
                    </Box>
                  ) : (
                    <>
                      <h1
                        onClick={() => setCategoryFilter("Scheduled")}
                        style={{ cursor: "pointer", color: "#0073bb" }}
                      >
                        {summary.scheduled_events}
                      </h1>
                      {summary.scheduled_events === 0
                        ? "No Scheduled Events"
                        : summary.scheduled_events === 1
                          ? "Needs Planning"
                          : "Need Planning"}
                    </>
                  )}
                </Box>
              </Container>
              <Container
                disableHeaderPaddings={true}
                disableContentPaddings={true}
                data-type="billingChanges"
                className={`category-container ${categoryFilter === "Billing" ? "selected" : ""}`}
              >
                <Box textAlign="center" margin={"l"}>
                  <h3>💰 Billing Changes</h3>
                  {loading ? (
                    <Box margin="m">
                      <Spinner size="normal" />
                    </Box>
                  ) : (
                    <>
                      <h1 onClick={() => setCategoryFilter("Billing")} style={{ cursor: "pointer", color: "#0073bb" }}>
                        {summary.billing_changes}
                      </h1>
                      {summary.billing_changes === 0
                        ? "No Billing Changes"
                        : summary.billing_changes === 1
                          ? "Account Affected"
                          : "Accounts Affected"}
                    </>
                  )}
                </Box>
              </Container>
            </Grid>
            <OrgHealthAccountNotificationTable />
          </SpaceBetween>
        </ContentLayout>
      }
      toolsContent={<HealthDashboardInfo />}
      toolsOpen={isInfoPanelOpen}
      onToolsChange={({ detail }: { detail: { open: boolean } }) => setIsInfoPanelOpen(detail.open)}
    />
  );
}
