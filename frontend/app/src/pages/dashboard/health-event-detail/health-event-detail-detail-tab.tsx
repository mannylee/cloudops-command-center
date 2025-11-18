import { Box, Container } from "@cloudscape-design/components";

export default function HealthEventDetailDetailTab({ eventDetail = "" }) {
  return (
    <Container>
      <Box>
        <div style={{ whiteSpace: "pre-line" }}>{eventDetail}</div>
      </Box>
    </Container>
  );
}
