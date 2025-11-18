import { get, post } from "aws-amplify/api";
import { ApiClientBase } from "./api-client-base";
import { API_NAME } from "../constants";
import { Feedback } from "../types";

export class FeedbackApiClient extends ApiClientBase {
  async getFeedback(): Promise<Feedback> {
    let retValue: Feedback = {
      feedback: "",
    };
    const headers = await this.getHeaders();
    const restOperation = get({
      apiName: API_NAME,
      path: "/feedback",
      options: {
        headers,
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? { feedback: "empty" };
    return retValue;
  }

  async updateFeedback({ feedback }: Feedback): Promise<Feedback> {
    let retValue: Feedback = {
      feedback: "",
    };
    const headers = await this.getHeaders();
    const restOperation = post({
      apiName: API_NAME,
      path: "/feedback",
      options: {
        headers,
        body: {
          feedback: feedback,
        },
      },
    });

    const response = await restOperation.response;
    const data = (await response.body?.json()) as any;
    retValue = data ?? [];
    return retValue;
  }
}
