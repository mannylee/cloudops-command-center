import { useEffect, useState } from "react";
import { CaseExpertAiResponse, HealthEventItem } from "../../../common/types";

import { Box, SpaceBetween } from "@cloudscape-design/components";

interface HealthEventDetailAiFixTabProp {
  event: HealthEventItem;
}

const initialCaseExpertAiResponse: CaseExpertAiResponse = {
  summary: "",
  impact: "",
  resolution: "",
};

export default function HealthEventDetailAiFixTab({ event }: HealthEventDetailAiFixTabProp) {
  // Suppress unused parameter warning
  void event;
  const [aiResponse, setAiResponse] = useState<CaseExpertAiResponse>(initialCaseExpertAiResponse);

  useEffect(() => {
    const getAiSuggestion = async () => {
      // AI functionality temporarily disabled
      const aiResponse = {
        summary: "AI analysis not available",
        impact: "Please check the event details manually",
        resolution: "Contact AWS support for assistance"
      };
      setAiResponse(aiResponse);
    };
    getAiSuggestion();
  }, []);

  return (
    <SpaceBetween size="xs">
      <Box>{aiResponse.summary}</Box>
      <Box>{aiResponse.impact}</Box>
      <Box>{aiResponse.resolution}</Box>
    </SpaceBetween>
  );
}
