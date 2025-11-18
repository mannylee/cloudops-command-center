import { BreadcrumbGroup, ContentLayout, SpaceBetween } from "@cloudscape-design/components";
import { useOnFollow } from "../../common/hooks/use-on-follow";
import BaseAppLayout from "../../components/base-app-layout";
import DashboardHeader from "./dashboard-header";
import StatisticsBlock from "./statistics-block";
import HealthCategoryTable from "./category-table";
import { APP_NAME } from "../../common/constants";

export default function DashboardPage() {
  const onFollow = useOnFollow();

  return (
    <BaseAppLayout
      breadcrumbs={
        <BreadcrumbGroup
          onFollow={onFollow}
          items={[
            {
              text: APP_NAME,
              href: "/",
            },
            {
              text: "Health Dashboard",
              href: "/",
            },
          ]}
        />
      }
      content={
        <ContentLayout header={<DashboardHeader />}>
          <SpaceBetween size="l">
            <StatisticsBlock />
            <HealthCategoryTable
              healthCategory={"CRITICAL"}
              healthItems={[]}
              tableTitle={`Top Priority Items`}
              pageSize={10}
            />
          </SpaceBetween>
        </ContentLayout>
      }
    />
  );
}
