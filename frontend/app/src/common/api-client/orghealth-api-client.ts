import { del, get, post, put } from "aws-amplify/api";
import { ApiClientBase } from "./api-client-base";
import { API_NAME } from "../constants";
import { OrgHealthEvent, OrgHealthFilter, OrgHealthSummary } from "../types";

export class OrgHealthApiClient extends ApiClientBase {
  async getOrgHealthFilter(): Promise<OrgHealthFilter[]> {
    let retValue: OrgHealthFilter[] = [];
    const headers = await this.getHeaders();
    const restOperation = get({
      apiName: API_NAME,
      path: "/filters",
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? [];
    return retValue;
  }

  async createOrgHealthFilter(filter: OrgHealthFilter): Promise<OrgHealthFilter> {
    const headers = await this.getHeaders();
    const restOperation = post({
      apiName: API_NAME,
      path: "/filters",
      options: {
        headers,
        body: {
          filterName: filter.filterName,
          description: filter.description,
          accountIds: filter.accountIds,
        },
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    return data;
  }

  async deleteOrgHealthFilter(filterId: string): Promise<void> {
    const headers = await this.getHeaders();
    const restOperation = del({
      apiName: API_NAME,
      path: `/filters/${filterId}`,
      options: {
        headers,
      },
    });

    await restOperation.response;
    return;
  }

  async updateOrgHealthFilter(filter: OrgHealthFilter): Promise<OrgHealthFilter> {
    const headers = await this.getHeaders();
    const restOperation = put({
      apiName: API_NAME,
      path: `/filters/${filter.filterId}`,
      options: {
        headers,
        body: {
          filterName: filter.filterName,
          description: filter.description,
          accountIds: filter.accountIds,
        },
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    return data;
  }

  async getOrgHealthSummary(filterId?: string): Promise<OrgHealthSummary> {
    let retValue: OrgHealthSummary;
    const headers = await this.getHeaders();
    const path = filterId ? `/dashboard/summary?filterId=${filterId}` : "/dashboard/summary";
    const restOperation = get({
      apiName: API_NAME,
      path: path,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? {};
    return retValue;
  }

  async getOrgHealthBillingEvents(filterId?: string): Promise<OrgHealthEvent[]> {
    let retValue: OrgHealthEvent[] = [];
    const headers = await this.getHeaders();
    const path = filterId ? `/events/billing/${filterId}` : "/events/billing";
    const restOperation = get({
      apiName: API_NAME,
      path,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data.data ?? [];
    return retValue;
  }

  async getOrgHealthIssuesEvents(filterId?: string): Promise<OrgHealthEvent[]> {
    let retValue: OrgHealthEvent[] = [];
    const headers = await this.getHeaders();
    const path = filterId ? `/events/issues/${filterId}` : "/events/issues";
    const restOperation = get({
      apiName: API_NAME,
      path,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data.data ?? [];
    return retValue;
  }

  async getOrgHealthNotificationsEvents(filterId?: string): Promise<OrgHealthEvent[]> {
    let retValue: OrgHealthEvent[] = [];
    const headers = await this.getHeaders();
    const path = filterId ? `/events/notifications/${filterId}` : "/events/notifications";
    const restOperation = get({
      apiName: API_NAME,
      path,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data.data ?? [];
    return retValue;
  }

  async getOrgHealthScheduledEvents(filterId?: string): Promise<OrgHealthEvent[]> {
    let retValue: OrgHealthEvent[] = [];
    const headers = await this.getHeaders();
    const path = filterId ? `/events/scheduled/${filterId}` : "/events/scheduled";
    const restOperation = get({
      apiName: API_NAME,
      path,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data.data ?? [];
    return retValue;
  }
}
