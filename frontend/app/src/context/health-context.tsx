import { createContext, useContext, useState, ReactNode } from "react";
import { HealthEventItem, HealthPriorityStat } from "../common/types";

interface HealthContextType {
  priorityStats: HealthPriorityStat[];
  setPriorityStats: (stats: HealthPriorityStat[]) => void;
  isPriorityStatsLoaded: boolean;
  setIsPriorityStatsLoaded: (isLoaded: boolean) => void;
  categoryItems: Record<string, HealthEventItem[]>;
  setCategoryItems: (category: string, items: HealthEventItem[]) => void;
  isCategoryLoaded: (category: string) => boolean;
  setCategoryLoaded: (category: string, isLoaded: boolean) => void;
  eventDetails: Record<string, HealthEventItem>;
  setEventDetail: (arn: string, event: HealthEventItem) => void;
  getEventDetail: (arn: string) => HealthEventItem | undefined;
}

const HealthContext = createContext<HealthContextType | undefined>(undefined);

export function HealthProvider({ children }: { children: ReactNode }) {
  const [priorityStats, setPriorityStats] = useState<HealthPriorityStat[]>([]);
  const [isPriorityStatsLoaded, setIsPriorityStatsLoaded] = useState(false);
  const [categoryItems, setCategoryItemsState] = useState<Record<string, HealthEventItem[]>>({});
  const [loadedCategories, setLoadedCategories] = useState<Record<string, boolean>>({});
  const [eventDetails, setEventDetails] = useState<Record<string, HealthEventItem>>({});

  const setCategoryItems = (category: string, items: HealthEventItem[]) => {
    setCategoryItemsState((prev) => ({
      ...prev,
      [category.toUpperCase()]: items,
    }));
  };

  const isCategoryLoaded = (category: string) => {
    return !!loadedCategories[category.toUpperCase()];
  };

  const setCategoryLoaded = (category: string, isLoaded: boolean) => {
    setLoadedCategories((prev) => ({
      ...prev,
      [category.toUpperCase()]: isLoaded,
    }));
  };

  const setEventDetail = (arn: string, event: HealthEventItem) => {
    setEventDetails((prev) => ({
      ...prev,
      [arn]: event,
    }));
  };

  const getEventDetail = (arn: string) => {
    return eventDetails[arn];
  };

  return (
    <HealthContext.Provider
      value={{
        priorityStats,
        setPriorityStats,
        isPriorityStatsLoaded,
        setIsPriorityStatsLoaded,
        categoryItems,
        setCategoryItems,
        isCategoryLoaded,
        setCategoryLoaded,
        eventDetails,
        setEventDetail,
        getEventDetail,
      }}
    >
      {children}
    </HealthContext.Provider>
  );
}

export function useHealth() {
  const context = useContext(HealthContext);
  if (context === undefined) {
    throw new Error("useHealth must be used within a HealthProvider");
  }
  return context;
}
