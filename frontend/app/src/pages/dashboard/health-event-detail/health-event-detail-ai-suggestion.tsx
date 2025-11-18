import {
  Box,
  Button,
  Container,
  Header,
  Icon,
  Popover,
  SpaceBetween,
  Spinner,
  StatusIndicator,
  Tabs,
  TextContent,
} from "@cloudscape-design/components";
import { HealthEventItem } from "../../../common/types";
import { CodeView } from "@cloudscape-design/code-view";
import { APP_NAME } from "../../../common/constants";

interface HealthEventDetailDetailBoxProps {
  event: HealthEventItem;
  loading: boolean;
}

export default function HealthEventDetailAiSuggestion({ event, loading }: HealthEventDetailDetailBoxProps) {
  return (
    <Container
      header={
        <Header
          variant="h2"
          actions={
            <SpaceBetween direction="horizontal" size="xs">
              <Popover
                dismissButton={false}
                position="top"
                size="small"
                triggerType="custom"
                content={<StatusIndicator type="success">Woof! Thank you!</StatusIndicator>}
              >
                <Button iconName="thumbs-up"></Button>
              </Popover>
              <Popover
                dismissButton={false}
                position="top"
                size="small"
                triggerType="custom"
                content={<StatusIndicator type="info">Feedback is a Gift!</StatusIndicator>}
              >
                <Button iconName="thumbs-down"></Button>
              </Popover>
            </SpaceBetween>
          }
        >
          <SpaceBetween direction="horizontal" size="m">
            <Icon name="gen-ai" size="medium" variant="success" />
            <Box variant="h2">{APP_NAME} AI Suggestion</Box>
          </SpaceBetween>
        </Header>
      }
    >
      {loading ? (
        <Spinner size="large" />
      ) : (
        <Tabs
          tabs={[
            {
              label: "Priority",
              id: "first",
              content: (
                <SpaceBetween size="xs">
                  <Box variant="h4">Suggested Priority</Box>
                  <TextContent>{event.priority}</TextContent>
                  <Box variant="h4">Reasons</Box>
                  <TextContent>
                    {event.reasons.map((item, index) => (
                      <li key={index}>{item}</li>
                    ))}
                  </TextContent>
                </SpaceBetween>
              ),
            },
            {
              label: "Impact",
              id: "Impact",
              content: (
                <TextContent>
                  {event.impact.map((item, index) => (
                    <li key={index}>{item}</li>
                  ))}
                </TextContent>
              ),
            },
            {
              label: (
                <SpaceBetween direction="horizontal" size="xs">
                  <Icon name="gen-ai" size="medium" variant="success" />
                  <Box variant="h4">AI Fix</Box>
                </SpaceBetween>
              ),
              id: "aifix",
              content: (
                <SpaceBetween size="m">
                  {event.resolution.map((item, index) => (
                    <Box key={index}>
                      <SpaceBetween size="xs">
                        <TextContent>
                          <b>
                            {index + 1}. {item.description}
                          </b>
                        </TextContent>
                        <CodeView content={item.action} />
                      </SpaceBetween>
                    </Box>
                  ))}
                </SpaceBetween>
              ),
            },
          ]}
        />
      )}
    </Container>
  );
}
