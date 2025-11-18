import {
  Container,
  Header,
  ColumnLayout,
  Box,
  SpaceBetween,
  Button,
  Icon,
  Spinner,
} from "@cloudscape-design/components";
import { useEffect, useState } from "react";
import { ApiClient } from "../../common/api-client/api-client";
import { HealthPriorityStat } from "../../common/types";
import RouterLink from "../../components/wrappers/router-link";
import { EVENT_PRIORITY } from "../../common/constants";
import { useHealth } from "../../context/health-context";

export default function StatisticsBlock() {
  const [loading, setLoading] = useState(true);
  const [numCritical, setNumCritical] = useState<number>(0);
  const [numHigh, setNumHigh] = useState<number>(0);
  const [numMedium, setNumMedium] = useState<number>(0);
  const [numLow, setNumLow] = useState<number>(0);
  const { 
    priorityStats, 
    setPriorityStats, 
    isPriorityStatsLoaded, 
    setIsPriorityStatsLoaded 
  } = useHealth();

  useEffect(() => {
    if (!isPriorityStatsLoaded) {
      fetchData();
    } else {
      updateCountsFromStats(priorityStats);
      setLoading(false);
    }
  }, [isPriorityStatsLoaded, priorityStats]);

  function updateCountsFromStats(stats: HealthPriorityStat[]) {
    stats.forEach((stat: HealthPriorityStat) => {
      if (stat.priority === EVENT_PRIORITY.critical) {
        setNumCritical(stat.count);
      } else if (stat.priority === EVENT_PRIORITY.high) {
        setNumHigh(stat.count);
      } else if (stat.priority === EVENT_PRIORITY.medium) {
        setNumMedium(stat.count);
      } else if (stat.priority === EVENT_PRIORITY.low) {
        setNumLow(stat.count);
      }
    });
  }

  async function fetchData() {
    setLoading(true);
    try {
      const apiClient = new ApiClient();
      const stats = await apiClient.health.getHealthPriorityStat();
      
      setPriorityStats(stats);
      setIsPriorityStatsLoaded(true);
      updateCountsFromStats(stats);
    } catch (error) {
      console.error("Error fetching health priority stats:", error);
    } finally {
      setLoading(false);
    }
  }

  return (
    <Container
      header={
        <Header
          variant="h2"
          actions={
            <SpaceBetween direction="horizontal" size="xs">
              <Button onClick={() => {
                setIsPriorityStatsLoaded(false);
                fetchData();
              }}>
                {" "}
                <Icon name="refresh" />{" "}
              </Button>
            </SpaceBetween>
          }
        >
          Priority Items
        </Header>
      }
    >
      <ColumnLayout columns={4} variant="text-grid">
        <div>
          <Box variant="awsui-key-label" data-stat-text="security-concern">
            <Box color="text-status-error" variant="h3">
              Critical Event
            </Box>
          </Box>
          {loading ? (
            <Spinner size="large" />
          ) : (
            <RouterLink href="/health/category/critical">
              <div style={{ padding: "0.8rem 0", fontSize: "2.5rem" }}>{numCritical}</div>
            </RouterLink>
          )}
        </div>
        <div>
          <Box color="text-status-warning" variant="h3">
            High Risk
          </Box>
          {loading ? (
            <Spinner size="large" />
          ) : (
            <RouterLink href="/health/category/high">
              <div style={{ padding: "0.8rem 0", fontSize: "2.5rem" }}>{numHigh}</div>
            </RouterLink>
          )}
        </div>
        <div>
          <Box color="text-status-info" variant="h3">
            Medium Risk
          </Box>
          {loading ? (
            <Spinner size="large" />
          ) : (
            <RouterLink href="/health/category/medium">
              <div style={{ padding: "0.8rem 0", fontSize: "2.5rem" }}>{numMedium}</div>
            </RouterLink>
          )}
        </div>
        <div>
          <Box color="text-status-success" variant="h3">
            Low Risk
          </Box>
          {loading ? (
            <Spinner size="large" />
          ) : (
            <RouterLink href="/health/category/low">
              <div style={{ padding: "0.8rem 0", fontSize: "2.5rem" }}>{numLow}</div>
            </RouterLink>
          )}
        </div>
      </ColumnLayout>
    </Container>
  );
}
