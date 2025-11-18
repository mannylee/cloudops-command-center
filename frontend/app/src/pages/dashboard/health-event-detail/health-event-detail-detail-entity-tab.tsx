import { Box, SpaceBetween, Table } from "@cloudscape-design/components";
import { HealthEventEntity } from "../../../common/types";

interface HealthEventDetailEntityTabProps {
  entities: HealthEventEntity[];
}

export default function HealthEventDetailEntityTab({ entities }: HealthEventDetailEntityTabProps) {
  return (
    <Table
      renderAriaLive={({ firstIndex, lastIndex, totalItemsCount }) =>
        `Displaying items ${firstIndex} to ${lastIndex} of ${totalItemsCount}`
      }
      columnDefinitions={[
        {
          id: "accountId",
          header: "Account ID",
          cell: (item) => item.awsAccountId || "-",
          sortingField: "accountId",
          isRowHeader: true,
        },
        {
          id: "entity",
          header: "Resource Entity",
          cell: (item) => item.entityValue || "-",
        },
        {
          id: "statusCode",
          header: "Status",
          cell: (item) => item.statusCode || "-",
        },
      ]}
      enableKeyboardNavigation
      items={entities}
      loadingText="Loading resources"
      sortingDisabled
      empty={
        <Box margin={{ vertical: "xs" }} textAlign="center" color="inherit">
          <SpaceBetween size="m">
            <b>No resources</b>
          </SpaceBetween>
        </Box>
      }
    />
  );
}
