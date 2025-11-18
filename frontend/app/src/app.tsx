import { HashRouter, BrowserRouter, Routes, Route, Outlet } from "react-router-dom";
import { USE_BROWSER_ROUTER } from "./common/constants";
import GlobalHeader from "./components/global-header";
import NotFound from "./pages/not-found";
import "@cloudscape-design/global-styles/index.css";
import "./styles/app.scss";
import OrganizationHealthDashboardPage from "./pages/organization-health/organization-health-page";
import OrgHealthFilterPage from "./pages/organization-health/filter-page/org-health-filter-page";
import EventDetailPage from "./pages/organization-health/event-detail/event-detail-page";

export default function App() {
  const Router = USE_BROWSER_ROUTER ? BrowserRouter : HashRouter;

  return (
    <div style={{ height: "100%" }}>
      <Router>
        <GlobalHeader />
        <div style={{ height: "56px", backgroundColor: "#000716" }}>&nbsp;</div>
        <div>
          <Routes>
            <Route index path="/" element={<OrganizationHealthDashboardPage />} />

            <Route path="/organization-health-dashboard" element={<Outlet />}>
              <Route path="" element={<OrganizationHealthDashboardPage />} />
              <Route path="filter" element={<OrgHealthFilterPage />} />
              <Route path="event/:eventArn" element={<EventDetailPage />} />
            </Route>

            <Route path="*" element={<NotFound />} />
          </Routes>
        </div>
      </Router>
    </div>
  );
}
