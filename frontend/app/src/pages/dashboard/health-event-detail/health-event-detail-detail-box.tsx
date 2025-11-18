import { Container, KeyValuePairs, Spinner } from "@cloudscape-design/components";
import { HealthEventItem } from "../../../common/types";
import { TextHelper } from "../../../common/helpers/text-helper";

interface HealthEventDetailDetailBoxProps {
  event: HealthEventItem;
  loading: boolean;
}

export default function HealthEventDetailDetailBox({ event, loading }: HealthEventDetailDetailBoxProps) {
  return (
    <Container>
      {loading ? (
        <Spinner size="large" />
      ) : (
        <KeyValuePairs
          columns={3}
          items={[
            {
              type: "group",
              items: [
                {
                  label: "Event Name",
                  value: TextHelper.formatEventName(event.eventTypeCode),
                },
                {
                  label: "Event Date",
                  value: TextHelper.formatTimestamp(event.startTime),
                },
                {
                  label: "Cloud Provider",
                  value: (
                    <>
                      {event.cloudProvider && (
                        <img
                          src={`/images/${event.cloudProvider.toLowerCase()}-logo.png`}
                          alt={`${event.cloudProvider} logo`}
                          style={{ height: "35px", verticalAlign: "middle", marginLeft: "5px" }}
                        />
                      )}
                    </>
                  ),
                },
              ],
            },
            {
              type: "group",
              items: [
                {
                  label: "Region",
                  value: event.region,
                },
                {
                  label: "Service",
                  value: event.service,
                },
              ],
            },
            {
              type: "group",
              items: [
                {
                  label: "Status",
                  value: event.statusCode,
                },
                {
                  label: "Last Update",
                  value: TextHelper.formatTimestamp(event.lastUpdatedTime),
                },
              ],
            },
          ]}
        ></KeyValuePairs>
      )}
    </Container>
  );
}
