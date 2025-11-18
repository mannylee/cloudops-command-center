import Table, { TableProps } from "@cloudscape-design/components/table";
import Box from "@cloudscape-design/components/box";
import SpaceBetween from "@cloudscape-design/components/space-between";
import RouterLink from "../../components/wrappers/router-link";
import { Badge, Button, Header, Pagination, PropertyFilter } from "@cloudscape-design/components";
import { useOrgHealth } from "../../context/org-health-context";
import { useCollection } from "@cloudscape-design/collection-hooks";
import { OrgHealthEvent } from "../../common/types";
import { TextHelper } from "../../common/helpers/text-helper";
import { formatLastUpdateTime } from "../../common/helpers/date-helper";

interface OrgHealthAccountNotificationTableProps {
  loading?: boolean;
}

const ItemsColumnDefinitions: TableProps.ColumnDefinition<OrgHealthEvent>[] = [
  {
    id: "eventType",
    header: "Event Type",
    cell: (item) => (
      <RouterLink href={`/organization-health-dashboard/event/${encodeURIComponent(item.eventArn)}`}>
        {item.simplifiedDescription}
      </RouterLink>
    ),
    sortingField: "eventType",
    maxWidth: 300,
  },
  {
    id: "impactAnalysis",
    header: "Impact Analysis",
    cell: (item) => item.impactAnalysis || "-",
    sortingField: "impactAnalysis",
    minWidth: 300,
    maxWidth: 350,
  },
  {
    id: "riskLevel",
    header: "Priority",
    cell: (item) => {
      if (item.riskLevel.toLowerCase() === "critical") {
        return (
          <Badge color="severity-critical">
            Critical
          </Badge>
        );
      } else if (item.riskLevel.toLowerCase() === "high") {
        return (
          <Badge color="severity-high">
            High
          </Badge>
        );
      } else if (item.riskLevel.toLowerCase() === "medium") {
        return (
          <Badge color="severity-medium">
            Medium
          </Badge>
        );
      } else if (item.riskLevel.toLowerCase() === "low") {
        return (
          <Badge color="severity-low">
            Low
          </Badge>
        );
      }
    },
    sortingField: "riskLevel",
  },
  {
    id: "accountIds",
    header: "Affected Account",
    cell: (item) => {
      const accountList = TextHelper.formatAccountIdsList(item.accountIds);
      return accountList.length > 0 ? (
        <ul style={{ margin: 0, paddingLeft: '16px' }}>
          {accountList.map((account, index) => (
            <li key={index}>{account}</li>
          ))}
        </ul>
      ) : "-";
    },
    sortingField: "accountIds",
  },
  {
    id: "lastUpdateTime",
    header: "Last Updated Time",
    cell: (item) => formatLastUpdateTime(item.lastUpdateTime),
    sortingField: "lastUpdateTime",
  },
];

export default function OrgHealthAccountNotificationTable({
  loading: externalLoading = false,
}: OrgHealthAccountNotificationTableProps) {
  const { filteredEvents, loading, categoryFilter, setCategoryFilter } = useOrgHealth();

  const downloadCSV = () => {
    const headers = ["Event Type", "Impact Analysis", "Required Actions", "Consequences If Ignored", "Priority", "Affected Account", "Last Updated Time"];
    const csvContent = [
      headers.join(","),
      ...filteredEvents.map((item) =>
        [
          `"${item.simplifiedDescription || ""}",`,
          `"${item.impactAnalysis || "-"}",`,
          `"${item.requiredActions || "-"}",`,
          `"${item.consequencesIfIgnored || "-"}",`,
          `"${item.riskLevel || "-"}",`,
          `"${TextHelper.formatAccountIds(item.accountIds)}",`,
          `"${formatLastUpdateTime(item.lastUpdateTime)}"`,
        ].join("")
      ),
    ].join("\n");

    const blob = new Blob([csvContent], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `health-events-${new Date().toISOString().split("T")[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const { items, filteredItemsCount, collectionProps, propertyFilterProps, paginationProps } = useCollection(
    filteredEvents,
    {
      propertyFiltering: {
        filteringProperties: [
          {
            key: "eventType",
            operators: ["=", "!="],
            propertyLabel: "Event Type",
            groupValuesLabel: "Event Type values",
          },
          {
            key: "impactAnalysis",
            operators: ["=", "!=", ":"],
            propertyLabel: "Impact Analysis",
            groupValuesLabel: "Impact Analysis values",
          },
          {
            key: "riskLevel",
            operators: ["=", "!="],
            propertyLabel: "Priority",
            groupValuesLabel: "Priority values",
          },
        ],
        empty: (
          <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
            <SpaceBetween size="xxs">
              <div>
                <b>No Health Event</b>
              </div>
            </SpaceBetween>
          </Box>
        ),
        noMatch: (
          <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
            <SpaceBetween size="xxs">
              <div>
                <b>No Health Event</b>
              </div>
            </SpaceBetween>
          </Box>
        ),
      },
      pagination: { pageSize: 50 },
      sorting: {
        defaultState: {
          sortingColumn: ItemsColumnDefinitions.find((col) => col.id === "eventType")!,
        },
      },
    }
  );
  return (
    <Table
      {...collectionProps}
      columnDefinitions={ItemsColumnDefinitions}
      header={
        <Header
          actions={
            <SpaceBetween direction="horizontal" size="xs">
              <Button onClick={downloadCSV}>Download</Button>
              {categoryFilter && <Button onClick={() => setCategoryFilter(null)}>Clear Category</Button>}
            </SpaceBetween>
          }
        >
          {categoryFilter ? `${categoryFilter} Events` : "All Health Events"}
        </Header>
      }
      items={items}
      filter={
        <PropertyFilter
          {...propertyFilterProps}
          countText={TextHelper.getTextFilterCounterText(filteredItemsCount)}
          enableTokenGroups
          expandToViewport
        />
      }
      pagination={<Pagination {...paginationProps} />}
      loading={loading || externalLoading}
      wrapLines
      // renderAriaLive={({ firstIndex, lastIndex, totalItemsCount }) =>
      //   `Displaying items ${firstIndex} to ${lastIndex} of ${totalItemsCount}`
      // }
      // columnDefinitions={[]}
      // enableKeyboardNavigation
      // items={(Array.isArray(events) ? events : []).map((event) => ({
      //   eventArn: event.eventArn,
      //   eventType: event.eventType || "-",
      //   eventDescription: event.consequencesIfIgnored || "-",
      //   priority: event.riskLevel?.toLowerCase() || "medium",
      //   affectedAccount: event.accountIds?.join(", ") || "-",
      //   count: event.accountIds?.length.toString() || "0",
      // }))}
      // loadingText="Loading Health Event"
      // loading={loading || externalLoading}
      // wrapLines
      empty={
        <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
          <SpaceBetween size="m">
            <b>No Health Event</b>
          </SpaceBetween>
        </Box>
      }
    />
  );
}
