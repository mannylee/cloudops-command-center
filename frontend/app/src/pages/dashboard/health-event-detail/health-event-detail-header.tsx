import { Header } from "@cloudscape-design/components";

export default function HealthEventDetailPageHeader({ eventName = "" }) {
  return <Header variant="h1">{eventName}</Header>;
}
