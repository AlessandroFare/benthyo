import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { motion } from "framer-motion";
import type { AuthUser } from "@/lib/auth";
import { Sidebar } from "@/components/layout/Sidebar";
import { TopBar } from "@/components/layout/TopBar";
import { ToastProvider } from "@/components/shared/Toast";

interface DashboardLayoutProps {
  user: AuthUser | null;
}

export function DashboardLayout({ user }: DashboardLayoutProps) {
  const location = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  return (
    <ToastProvider>
      <div className="flex h-full bg-background text-foreground">
        <Sidebar
          mobileOpen={mobileNavOpen}
          onNavigate={() => setMobileNavOpen(false)}
        />
        <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <TopBar user={user} onOpenMobileNav={() => setMobileNavOpen(true)} />
          <main className="flex-1 overflow-y-auto bg-background p-4 sm:p-6">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.15 }}
            >
              <Outlet />
            </motion.div>
          </main>
        </div>
      </div>
    </ToastProvider>
  );
}
