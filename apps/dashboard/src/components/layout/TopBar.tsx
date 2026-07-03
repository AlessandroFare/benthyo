import { useLocation } from "react-router-dom";
import { Bell, LogOut, Menu, Search } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import type { AuthUser } from "@/lib/auth";
import { signOut } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { ThemeToggle } from "@/components/layout/ThemeToggle";

const pageTitles: Record<string, string> = {
  "/": "Today",
  "/sites": "Dive Sites",
  "/customers": "Customers",
  "/slots": "Trip Slots",
  "/rental-gear": "Rental Gear",
  "/analytics": "Analytics",
  "/species": "Species",
  "/marketplace": "Marketplace",
  "/corrections": "Corrections",
  "/settings": "Settings",
};

function getPageTitle(pathname: string): string {
  if (pathname.startsWith("/customers/")) return "Customer Detail";
  if (pathname.startsWith("/species/")) return "Species Detail";
  return pageTitles[pathname] ?? "Benthyo";
}

interface TopBarProps {
  user: AuthUser | null;
  onOpenMobileNav: () => void;
}

export function TopBar({ user, onOpenMobileNav }: TopBarProps) {
  const { pathname } = useLocation();
  const title = getPageTitle(pathname);

  async function handleSignOut() {
    await signOut();
  }

  return (
    <header className="sticky top-0 z-30 flex h-16 items-center justify-between gap-2 border-b border-border bg-background/80 px-4 backdrop-blur-md sm:px-6">
      <div className="flex min-w-0 items-center gap-2">
        <Button
          variant="ghost"
          size="icon"
          onClick={onOpenMobileNav}
          aria-label="Open navigation menu"
          className="-ml-2 text-muted-foreground hover:bg-accent hover:text-foreground sm:hidden"
        >
          <Menu className="h-5 w-5" />
        </Button>
        <div className="min-w-0">
          {/* Title transitions when navigating */}
          <AnimatePresence mode="wait" initial={false}>
            <motion.h1
              key={title}
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.18, ease: "easeOut" }}
              className="truncate text-xl font-semibold text-foreground"
            >
              {title}
            </motion.h1>
          </AnimatePresence>
          <p className="hidden text-xs text-muted-foreground sm:block">
            Benthyo Operator Dashboard
          </p>
        </div>
      </div>

      <div className="flex items-center gap-2">
        {/* Search */}
        <div className="relative hidden md:block">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search..."
            className="w-56 border-border bg-card pl-9 text-foreground placeholder:text-muted-foreground/60 focus-visible:ring-primary/40"
            aria-label="Search"
          />
        </div>

        {/* Theme toggle */}
        <ThemeToggle />

        {/* Notifications */}
        <Button
          variant="ghost"
          size="icon"
          aria-label="Notifications"
          className="text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <Bell className="h-4 w-4" />
        </Button>

        <Separator orientation="vertical" className="h-8 bg-border" />

        {/* User */}
        <div className="flex items-center gap-3">
          <div className="hidden text-right sm:block">
            <p className="text-sm font-medium text-foreground leading-none">
              {user?.user_metadata?.full_name ?? user?.email ?? "Operator"}
            </p>
            <p className="mt-0.5 text-xs text-muted-foreground">{user?.email}</p>
          </div>
          {/* Avatar initials */}
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-ocean-500 text-xs font-semibold text-white">
            {(user?.user_metadata?.full_name ?? user?.email ?? "O")
              .charAt(0)
              .toUpperCase()}
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={handleSignOut}
            aria-label="Sign out"
            className="text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </header>
  );
}
