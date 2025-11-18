import { BreadcrumbGroup, SpaceBetween } from "@cloudscape-design/components";
import BaseAppLayout from "../../components/base-app-layout";
import { useOnFollow } from "../../common/hooks/use-on-follow";
import { APP_NAME } from "../../common/constants";
import HealthCategoryTable from "./category-table";
import { useParams } from "react-router-dom";
import { useEffect, useState } from "react";
import StatisticsBlock from "./statistics-block";

export default function HealthCategoryPage() {
  const onFollow = useOnFollow();
  const { category } = useParams();
  const [categoryDesc, setCategoryDesc] = useState<string>("");

  useEffect(() => {
    setCategoryDesc(getCategoryText(category!));
  }, [category]);

  function getCategoryText(category: string): string {
    switch (category.toLocaleUpperCase()) {
      case "CRITICAL":
        return "Critical Event";
      case "HIGH":
        return "High Risk";
      case "MEDIUM":
        return "Medium Risk";
      case "LOW":
        return "Low Risk";
      default:
        return "Unknown Category";
    }
  }

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
              text: "Health",
              href: "/",
            },
            {
              text: categoryDesc,
              href: "#",
            },
          ]}
        />
      }
      content={
        <SpaceBetween size="l">
          <StatisticsBlock />
          <HealthCategoryTable
            healthCategory={category!}
            healthItems={[]}
            tableTitle={`${categoryDesc} Items`}
            pageSize={40}
          />
        </SpaceBetween>
      }
    />
  );
}
