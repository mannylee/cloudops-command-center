import { SideNavigation, SideNavigationProps } from "@cloudscape-design/components";
import { useNavigationPanelState } from "../common/hooks/use-navigation-panel-state";
import { useState } from "react";
import { useOnFollow } from "../common/hooks/use-on-follow";
import { useLocation } from "react-router-dom";
import "../styles/app.scss";


export default function NavigationPanel() {
  const location = useLocation();
  const onFollow = useOnFollow();
  const [navigationPanelState, setNavigationPanelState] = useNavigationPanelState();

  const [items] = useState<SideNavigationProps.Item[]>(() => {
    const items: SideNavigationProps.Item[] = [
      {
        type: "link",
        text: "Health Event Intelligence",
        href: "/organization-health-dashboard",
      },
    ];

    return items;
  });

  const onChange = ({ detail }: { detail: SideNavigationProps.ChangeDetail }) => {
    const sectionIndex = items.indexOf(detail.item);
    setNavigationPanelState({
      collapsedSections: {
        ...navigationPanelState.collapsedSections,
        [sectionIndex]: !detail.expanded,
      },
    });
  };

  return (
    <div className="navigation-wrapper">
      <SideNavigation
        onFollow={onFollow}
        onChange={onChange}
        activeHref={location.pathname}
        items={items.map((value, idx) => {
          if (value.type === "section") {
            const collapsed = navigationPanelState.collapsedSections?.[idx] === true;
            value.defaultExpanded = !collapsed;
          }

          return value;
        })}
      />
    </div>
  );
}
