import { useEffect, useState } from "react";
import { ApiClient } from "../../common/api-client/api-client";
import { HealthEventItem } from "../../common/types";
import {
  Box,
  Header,
  Pagination,
  PropertyFilter,
  SpaceBetween,
  StatusIndicator,
  Table,
  TableProps,
} from "@cloudscape-design/components";
import RouterLink from "../../components/wrappers/router-link";
import { useCollection } from "@cloudscape-design/collection-hooks";
import { TextHelper } from "../../common/helpers/text-helper";
import { useHealth } from "../../context/health-context";

const ItemsColumnDefinitions: TableProps.ColumnDefinition<HealthEventItem>[] = [
  {
    id: "eventTypeCode",
    header: "Event",
    sortingField: "eventTypeCode",
    cell: (item) => (
      <RouterLink href={`/health/event/${encodeURIComponent(item.arn)}`}>
        {TextHelper.formatEventName(item.eventTypeCode)}
      </RouterLink>
    ),
  },
  {
    id: "startTime",
    header: "Event Date",
    sortingField: "startTime",
    cell: (item) => TextHelper.formatTimestamp(item.startTime) || "-",
  },
  {
    id: "statusCode",
    header: "Status",
    sortingField: "statusCode",
    cell: (item) => {
      if (item.statusCode === "open") {
        return <StatusIndicator type="warning">Open</StatusIndicator>;
      } else if (item.statusCode === "closed") {
        return <StatusIndicator type="success">Closed</StatusIndicator>;
      } else if (item.statusCode === "upcoming") {
        return <StatusIndicator type="info">Coming Up</StatusIndicator>;
      }
    },
  },
  {
    id: "eventTypeCategory",
    header: "Event Type",
    sortingField: "eventTypeCategory",
    cell: (item) => item.eventTypeCategory || "-",
  },
  {
    id: "priority",
    header: "Priority",
    sortingField: "priority",
    cell: (item) => item.priority || "-",
  },
  {
    id: "cloudProvider",
    header: "Cloud Provider",
    sortingField: "cloudProvider",
    cell: (item) => {
      if (item.cloudProvider === "AWS") {
        return <img src="/images/aws-logo.png" height={"35"} />;
      } else if (item.cloudProvider === "Azure") {
        return <img src="/images/azure-logo.png" height={"35"} />;
      } else if (item.cloudProvider === "GCP") {
        return <img src="/images/gcp-logo.png" height={"35"} />;
      } else {
        return "-";
      }
    },
  },
];

interface HealthCategoryTableProps {
  healthCategory: string;
  healthItems: HealthEventItem[];
  tableTitle: string;
  pageSize: number;
}

export default function HealthCategoryTable({
  healthCategory = "",
  healthItems = [],
  tableTitle = "",
  pageSize = 10,
}: HealthCategoryTableProps) {
  const [loading, setLoading] = useState(true);
  const [allItems, setAllItems] = useState<HealthEventItem[]>([]);
  const { 
    categoryItems, 
    setCategoryItems, 
    isCategoryLoaded, 
    setCategoryLoaded 
  } = useHealth();
  const { items, filteredItemsCount, collectionProps, propertyFilterProps, paginationProps } = useCollection(allItems, {
    propertyFiltering: {
      filteringProperties: [
        {
          key: "eventTypeCode",
          operators: ["=", "!="],
          propertyLabel: "Event",
          groupValuesLabel: "Event Name values",
        },
        {
          key: "statusCode",
          operators: ["=", "!="],
          propertyLabel: "Status",
          groupValuesLabel: "Status values",
        },
        {
          key: "eventTypeCategory",
          operators: ["=", "!="],
          propertyLabel: "Event Type",
          groupValuesLabel: "Event Type values",
        },
        {
          key: "cloudProvider",
          operators: ["=", "!="],
          propertyLabel: "Cloud Provider",
          groupValuesLabel: "Cloud Provider values",
        },
      ],
      empty: (
        <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
          <SpaceBetween size="xxs">
            <div>
              <b>No Items</b>
              <Box variant="p" color="inherit">
                Item is a thing that is used to do something.
              </Box>
            </div>
          </SpaceBetween>
        </Box>
      ),
      noMatch: (
        <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
          <SpaceBetween size="xxs">
            <div>
              <b>No Items</b>
              <Box variant="p" color="inherit">
                Item is a thing that is used to do something.
              </Box>
            </div>
          </SpaceBetween>
        </Box>
      ),
    },
    pagination: { pageSize: pageSize },
    sorting: {
      defaultState: {
        sortingColumn: ItemsColumnDefinitions.find((col) => col.id === "startTime")!,
      },
    },
  });

  async function getHealthItems() {
    setLoading(true);

    if (healthItems.length > 0) {
      // health items supplied as prop
      setAllItems(healthItems);
      setLoading(false);
      return;
    }

    const category = healthCategory.toUpperCase();
    
    // Check if we already have data for this category in context
    if (isCategoryLoaded(category) && categoryItems[category]) {
      setAllItems(categoryItems[category]);
      setLoading(false);
      return;
    }

    try {
      // Get health items from API
      const apiClient = new ApiClient();
      const items = await apiClient.health.getHealthByPriority(category);
      
      // Update local state
      setAllItems(items);
      
      // Store in context
      setCategoryItems(category, items);
      setCategoryLoaded(category, true);
    } catch (error) {
      console.error(`Error fetching health items for category ${category}:`, error);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    getHealthItems();
  }, [healthCategory, healthItems]);

  return (
    <Table
      {...collectionProps}
      columnDefinitions={ItemsColumnDefinitions}
      items={items}
      header={<Header counter={`(${items.length.toString()})`}>{tableTitle}</Header>}
      filter={
        <PropertyFilter
          {...propertyFilterProps}
          countText={TextHelper.getTextFilterCounterText(filteredItemsCount)}
          enableTokenGroups
          expandToViewport
        />
      }
      pagination={<Pagination {...paginationProps} />}
      loading={loading}
      loadingText="Loading Items"
      variant="embedded"
    />
  );
}
