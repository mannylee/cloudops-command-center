import { ReactNode } from 'react';
import { HealthProvider } from './health-context';
import { OrgHealthProvider } from './org-health-context';

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <HealthProvider>
      <OrgHealthProvider>
        {children}
      </OrgHealthProvider>
    </HealthProvider>
  );
}