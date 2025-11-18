
import { FeedbackApiClient } from "./feedback-api-client";
import { HealthApiClient } from "./health-api-client";
import { OrgHealthApiClient } from "./orghealth-api-client";

export class ApiClient {
  private _healthClient: HealthApiClient | undefined;
  public get health() {
    if (!this._healthClient) {
      this._healthClient = new HealthApiClient();
    }
    return this._healthClient;
  }

  private _feedbackClient: FeedbackApiClient | undefined;
  public get feedback() {
    if (!this._feedbackClient) {
      this._feedbackClient = new FeedbackApiClient();
    }
    return this._feedbackClient;
  }

  private _orgHealthClient: OrgHealthApiClient | undefined;
  public get orgHealth() {
    if (!this._orgHealthClient) {
      this._orgHealthClient = new OrgHealthApiClient();
    }
    return this._orgHealthClient;
  }
}
