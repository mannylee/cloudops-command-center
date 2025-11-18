

export interface NavigationPanelState {
  collapsed?: boolean;
  collapsedSections?: Record<number, boolean>;
}



export interface HealthPriorityStat {
  priority: string;
  count: number;
}

export interface HealthEventEntity {
  awsAccountId: string;
  entityArn: string;
  entityUrl: string;
  entityValue: string;
  eventArn: string;
  lastUpdatedTime: number;
  statusCode: string;
  tags: string;
}

export interface HealthEventItemResolution {
  description: string;
  action: string;
}

export interface HealthEventItem {
  arn: string;
  details: string;
  endTime: string;
  entities: HealthEventEntity[];
  eventScopeCode: string;
  eventTypeCategory: string;
  eventTypeCode: string;
  lastUpdatedTime: number;
  priority: string;
  region: string;
  service: string;
  startTime: number;
  statusCode: string;
  reasons: string[];
  impact: string[];
  resolution: HealthEventItemResolution[];
  cloudProvider: string;
}

export interface BedrockAgentResponse {
  agent: "ASSISTANCE" | "PRIORITIZER" | "CASE_EXPERT";
  sessionId: string;
  completion: string;
}

export interface Feedback {
  feedback: string;
}

export interface CaseExpertAiResponse {
  summary: string;
  impact: string;
  resolution: string;
}

export interface OrgHealthFilter {
  filterId: string;
  filterName: string;
  description: string;
  accountIds: string[];
}

export interface OrgHealthSummary {
  notifications: number;
  active_issues: number;
  scheduled_events: number;
  billing_changes: number;
}

export interface OrgHealthEvent {
  eventArn: string;
  eventType: string;
  eventCategory: string;
  service: string;
  region: string;
  riskLevel: string;
  lastUpdateTime: string;
  consequencesIfIgnored: string;
  description: string;
  requiredActions: string;
  impactAnalysis: string;
  riskCategory: string;
  affectedResources: string;
  accountIds: { [accountId: string]: string }; // Changed from string[] to object mapping accountId to accountName
  simplifiedDescription: string;
}
