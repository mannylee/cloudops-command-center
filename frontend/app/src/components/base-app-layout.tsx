import React from "react";
import { AppLayout, AppLayoutProps } from "@cloudscape-design/components";
import { useNavigationPanelState } from "../common/hooks/use-navigation-panel-state";
import NavigationPanel from "./navigation-panel";
import { I18nProvider } from "@cloudscape-design/components/i18n";
import enMessages from "@cloudscape-design/components/i18n/messages/all.en.json";

interface BaseAppLayoutProps extends AppLayoutProps {
  toolsContent?: React.ReactNode;
  toolsOpen?: boolean;
  onToolsChange?: (event: { detail: { open: boolean } }) => void;
}

export default function BaseAppLayout({
  toolsContent,
  toolsOpen = false,
  onToolsChange,
  ...props
}: BaseAppLayoutProps) {
  const [navigationPanelState, setNavigationPanelState] = useNavigationPanelState();

  return (
    <I18nProvider locale="en" messages={[enMessages]}>
      <AppLayout
        headerSelector="#awsui-top-navigation"
        navigation={<NavigationPanel />}
        navigationOpen={!navigationPanelState.collapsed}
        onNavigationChange={({ detail }) => setNavigationPanelState({ collapsed: !detail.open })}
        tools={toolsContent}
        toolsOpen={toolsOpen}
        onToolsChange={onToolsChange}
        toolsHide={!toolsContent}
        {...props}
      />
    </I18nProvider>
  );
}
