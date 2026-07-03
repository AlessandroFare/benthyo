import { lazy, Suspense, type ReactNode } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { ProtectedRoute } from "@/components/auth/ProtectedRoute";
import { DashboardLayout } from "@/components/layout/DashboardLayout";
import { PageSkeleton } from "@/components/shared/LoadingSkeleton";
import { useAuth } from "@/contexts/AuthContext";

const LoginPage = lazy(() =>
  import("@/pages/Login").then((m) => ({ default: m.LoginPage })),
);
const DashboardPage = lazy(() =>
  import("@/pages/Dashboard").then((m) => ({ default: m.DashboardPage })),
);
const TodayPage = lazy(() => import("@/pages/Today"));
const SitesPage = lazy(() =>
  import("@/pages/Sites").then((m) => ({ default: m.SitesPage })),
);
const CustomersPage = lazy(() =>
  import("@/pages/Customers").then((m) => ({ default: m.CustomersPage })),
);
const CustomerDetailPage = lazy(() =>
  import("@/pages/CustomerDetail").then((m) => ({ default: m.CustomerDetailPage })),
);
const AnalyticsPage = lazy(() =>
  import("@/pages/Analytics").then((m) => ({ default: m.AnalyticsPage })),
);
const SpeciesPage = lazy(() =>
  import("@/pages/Species").then((m) => ({ default: m.SpeciesPage })),
);
const SpeciesDetailPage = lazy(() =>
  import("@/pages/SpeciesDetail").then((m) => ({ default: m.SpeciesDetailPage })),
);
const SettingsPage = lazy(() =>
  import("@/pages/Settings").then((m) => ({ default: m.SettingsPage })),
);
const CorrectionsPage = lazy(() =>
  import("@/pages/Corrections").then((m) => ({ default: m.CorrectionsPage })),
);
const RentalGearPage = lazy(() =>
  import("@/pages/RentalGear").then((m) => ({ default: m.RentalGearPage })),
);
const MarketplacePage = lazy(() =>
  import("@/pages/Marketplace").then((m) => ({ default: m.MarketplacePage })),
);
const SlotsPage = lazy(() =>
  import("@/pages/bookings/SlotsPage").then((m) => ({ default: m.SlotsPage })),
);
const EmbedBookingPage = lazy(() =>
  import("@/pages/EmbedBooking").then((m) => ({ default: m.EmbedBookingPage })),
);
const EmbedBriefingPage = lazy(() =>
  import("@/pages/EmbedBriefing").then((m) => ({ default: m.EmbedBriefingPage })),
);
const EmbedSitePage = lazy(() =>
  import("@/pages/EmbedSite").then((m) => ({ default: m.EmbedSitePage })),
);
const EmbedPrepPage = lazy(() =>
  import("@/pages/EmbedSite").then((m) => ({ default: m.EmbedPrepPage })),
);
const EmbedSiteGeneratorPage = lazy(() =>
  import("@/pages/EmbedSite").then((m) => ({ default: m.EmbedSiteGeneratorPage })),
);

function PageLoader({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<PageSkeleton />}>{children}</Suspense>
  );
}

export default function App() {
  const { user } = useAuth();

  return (
    <Routes>
      <Route
        path="/login"
        element={
          <PageLoader>
            <LoginPage />
          </PageLoader>
        }
      />
      <Route
        path="/embed/:slug/book"
        element={
          <PageLoader>
            <EmbedBookingPage />
          </PageLoader>
        }
      />
      <Route
        path="/embed/site/:slug"
        element={
          <PageLoader>
            <EmbedSitePage />
          </PageLoader>
        }
      />
      <Route
        path="/embed/site/:slug/generate"
        element={
          <PageLoader>
            <EmbedSiteGeneratorPage />
          </PageLoader>
        }
      />
      <Route
        path="/embed/site/:slug/prep"
        element={
          <PageLoader>
            <EmbedPrepPage />
          </PageLoader>
        }
      />
      <Route
        path="/embed/briefing/:slug"
        element={
          <PageLoader>
            <EmbedBriefingPage />
          </PageLoader>
        }
      />
      <Route
        element={
          <ProtectedRoute>
            <DashboardLayout user={user} />
          </ProtectedRoute>
        }
      >
        <Route
          index
          element={
            <PageLoader>
              <TodayPage />
            </PageLoader>
          }
        />
        <Route
          path="overview"
          element={
            <PageLoader>
              <DashboardPage />
            </PageLoader>
          }
        />
        <Route
          path="sites"
          element={
            <PageLoader>
              <SitesPage />
            </PageLoader>
          }
        />
        <Route
          path="customers"
          element={
            <PageLoader>
              <CustomersPage />
            </PageLoader>
          }
        />
        <Route
          path="customers/:id"
          element={
            <PageLoader>
              <CustomerDetailPage />
            </PageLoader>
          }
        />
        <Route
          path="analytics"
          element={
            <PageLoader>
              <AnalyticsPage />
            </PageLoader>
          }
        />
        <Route
          path="species"
          element={
            <PageLoader>
              <SpeciesPage />
            </PageLoader>
          }
        />
        <Route
          path="species/:id"
          element={
            <PageLoader>
              <SpeciesDetailPage />
            </PageLoader>
          }
        />
        <Route
          path="corrections"
          element={
            <PageLoader>
              <CorrectionsPage />
            </PageLoader>
          }
        />
        <Route
          path="rental-gear"
          element={
            <PageLoader>
              <RentalGearPage />
            </PageLoader>
          }
        />
        <Route
          path="slots"
          element={
            <PageLoader>
              <SlotsPage />
            </PageLoader>
          }
        />
        <Route
          path="marketplace"
          element={
            <PageLoader>
              <MarketplacePage />
            </PageLoader>
          }
        />
        <Route
          path="settings"
          element={
            <PageLoader>
              <SettingsPage />
            </PageLoader>
          }
        />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
