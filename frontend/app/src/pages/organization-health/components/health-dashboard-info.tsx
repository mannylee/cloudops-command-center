
import {
    Container,
    Header,
    Box,
    SpaceBetween,
    ExpandableSection,
    Link,
    Badge
} from '@cloudscape-design/components';

export default function HealthDashboardInfo() {
    return (
        <div className="sidebar-content">
            <SpaceBetween size="l">
                <Container header={<Header variant="h3">About Health Event Intelligence</Header>}>
                    <SpaceBetween size="m">
                        <Box>
                            The Health Event Intelligence dashboard provides a centralized view of AWS Health events
                            across your organization. It uses AI-powered analysis to help you understand the impact
                            and required actions for each event.
                        </Box>

                        <Box>
                            <strong>Key Features:</strong>
                            <ul style={{ marginTop: '8px', paddingLeft: '20px' }}>
                                <li>Real-time health event monitoring</li>
                                <li>AI-generated impact analysis</li>
                                <li>Automated risk categorization</li>
                                <li>Cross-account event consolidation</li>
                            </ul>
                        </Box>
                    </SpaceBetween>
                </Container>

                <Container header={<Header variant="h3">Event Categories</Header>}>
                    <SpaceBetween size="m">
                        <ExpandableSection headerText="📝 Notifications">
                            <Box>
                                <strong>Account notifications</strong> inform you about important changes,
                                updates, or actions required for your AWS account. These events typically
                                require your attention but are not service-impacting.
                            </Box>
                            <Box margin={{ top: 's' }}>
                                <Badge color="blue">Examples:</Badge> Security updates, policy changes,
                                service announcements
                            </Box>
                        </ExpandableSection>

                        <ExpandableSection headerText="🚨 Active Issues">
                            <Box>
                                <strong>Active issues</strong> represent ongoing problems that may impact
                                your AWS services. These require immediate attention and may affect your
                                application availability or performance.
                            </Box>
                            <Box margin={{ top: 's' }}>
                                <Badge color="red">Examples:</Badge> Service outages, degraded performance,
                                connectivity issues
                            </Box>
                        </ExpandableSection>

                        <ExpandableSection headerText="🗓️ Scheduled Events">
                            <Box>
                                <strong>Scheduled events</strong> are planned maintenance activities that
                                may temporarily impact your resources. Plan ahead to minimize disruption
                                to your applications.
                            </Box>
                            <Box margin={{ top: 's' }}>
                                <Badge color="grey">Examples:</Badge> Instance maintenance, network updates,
                                hardware replacements
                            </Box>
                        </ExpandableSection>

                        <ExpandableSection headerText="💰 Billing Changes">
                            <Box>
                                <strong>Billing changes</strong> notify you about modifications to pricing,
                                billing policies, or account-related financial matters that may affect
                                your AWS costs.
                            </Box>
                            <Box margin={{ top: 's' }}>
                                <Badge color="green">Examples:</Badge> Price changes, billing policy updates,
                                credit notifications
                            </Box>
                        </ExpandableSection>
                    </SpaceBetween>
                </Container>

                <Container header={<Header variant="h3">AI-Powered Analysis</Header>}>
                    <SpaceBetween size="m">
                        <Box>
                            Our system uses Amazon Bedrock to analyze each health event and provide:
                        </Box>

                        <Box>
                            <ul style={{ paddingLeft: '20px' }}>
                                <li><strong>Impact Analysis:</strong> Understanding of potential business impact</li>
                                <li><strong>Risk Assessment:</strong> Automated categorization (Critical, High, Medium, Low)</li>
                                <li><strong>Required Actions:</strong> Specific steps to address the event</li>
                                <li><strong>Consequences:</strong> What happens if the event is ignored</li>
                            </ul>
                        </Box>

                        <Box>
                            <span 
                                style={{ 
                                    borderRadius: '16px', 
                                    backgroundColor: '#e6f3ff',
                                    color: '#0073bb',
                                    marginRight: '8px',
                                    fontSize: '0.8em',
                                    padding: '4px 8px',
                                    display: 'inline-flex',
                                    alignItems: 'center',
                                    gap: '4px'
                                }}
                            >
                                🤖 AI Generated
                            </span> content is marked throughout the interface
                            to help you identify automated insights.
                        </Box>
                    </SpaceBetween>
                </Container>

                <Container header={<Header variant="h3">Filters & Management</Header>}>
                    <SpaceBetween size="m">
                        <Box>
                            Create custom filters to focus on specific AWS accounts within your organization.
                            Filters help you narrow down the health events to only the accounts you're interested in monitoring.
                        </Box>

                        <Box>
                            <strong>Current Filter Options:</strong>
                            <ul style={{ marginTop: '8px', paddingLeft: '20px' }}>
                                <li>Filter by specific AWS account IDs</li>
                                <li>Create named filters for easy reuse</li>
                                <li>Add descriptions to document filter purposes</li>
                            </ul>
                        </Box>

                        <Box>
                            Use the "Manage Filters" button to create, edit, or delete your custom account filters.
                            Once created, you can select a filter from the dropdown to apply it to the dashboard view.
                        </Box>
                    </SpaceBetween>
                </Container>

                <Container header={<Header variant="h3">Getting Help</Header>}>
                    <SpaceBetween size="s">
                        <Box>
                            <Link external href="https://docs.aws.amazon.com/health/">
                                AWS Health Documentation
                            </Link>
                        </Box>
                        <Box>
                            <Link external href="https://aws.amazon.com/premiumsupport/technology/personal-health-dashboard/">
                                Personal Health Dashboard Guide
                            </Link>
                        </Box>
                        <Box>
                            <Link href="/support">
                                Contact Support Team
                            </Link>
                        </Box>
                    </SpaceBetween>
                </Container>
            </SpaceBetween>
        </div>
    );
}