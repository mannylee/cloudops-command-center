import React from "react";
import ReactDOM from "react-dom/client";
import { StorageHelper } from "./common/helpers/storage-helper";
import "@cloudscape-design/global-styles/index.css";
import AppConfigured from "./components/app-configured";
import { APP_NAME } from "./common/constants";

const root = ReactDOM.createRoot(document.getElementById("root") as HTMLElement);

// Set document title from APP_NAME constant
document.title = APP_NAME;
document.querySelector('meta[name="description"]')?.setAttribute('content', APP_NAME);

const theme = StorageHelper.getTheme();
StorageHelper.applyTheme(theme);

root.render(
  <React.StrictMode>
    {/* <App /> */}
    <AppConfigured />
  </React.StrictMode>
);
