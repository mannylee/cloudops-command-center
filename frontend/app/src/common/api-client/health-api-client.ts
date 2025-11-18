import { get } from "aws-amplify/api";
import { ApiClientBase } from "./api-client-base";
import { API_NAME } from "../constants";
import { HealthEventItem, HealthPriorityStat } from "../types";

export class HealthApiClient extends ApiClientBase {
  async getHealthPriorityStat(): Promise<HealthPriorityStat[]> {
    let retValue: HealthPriorityStat[] = [];
    const headers = await this.getHeaders();
    const restOperation = get({
      apiName: API_NAME,
      path: "/health/priority-stat",
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? [];
    return retValue;
  }

  async getHealthByPriority(category: string): Promise<HealthEventItem[]> {
    let retValue: HealthEventItem[] = [];
    const headers = await this.getHeaders();
    const restOperation = get({
      apiName: API_NAME,
      path: `/health/category/${category}`,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? [];
    return retValue;
  }

  async getSingleHealthEvent(arn: string): Promise<HealthEventItem> {
    let retValue: HealthEventItem;
    const headers = await this.getHeaders();
    const restOperation = get({
      apiName: API_NAME,
      path: `/health/arn/${arn}`,
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? [];
    return retValue;
  }
}
