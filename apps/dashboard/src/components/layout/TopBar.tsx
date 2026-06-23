import { useLocation } from "react-router-dom";
import { Bell, LogOut, Menu, Search } from "lucide-react";
import type { AuthUser } from "@/lib/auth";
import { signOut } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";

const pageTitles: Record<string, string> = {
  "/": "Dashboard",
  "/sites": "Dive Sites",
  "/customers": "Customers",
  "/analytics": "Analytics",
  "/species": "Species",
  "/settings": "Settings",
};

function getPageTitle(pathname: string): string {
  if (pathname.startsWith("/customers/")) return "Customer Detail";
  if (pathname.startsWith("/species/")) return "Species Detail";
  return pageTitles[pathname] ?? "OceanLog";
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
    <header className="flex h-16 items-center justify-between gap-2 border-b border-border bg-background px-4 sm:px-6">
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
          <h1 className="truncate text-xl font-semibold text-foreground">{title}</h1>
          <p className="hidden text-sm text-muted-foreground sm:block">
            Manage your dive operation insights
          </p>
        </div>
      </div>

      <div className="flex items-center gap-4">
        <div className="relative hidden md:block">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search..."
            className="w-64 border-border bg-card pl-9 text-foreground placeholder:text-muted-foreground/70"
            aria-label="Search"
          />
        </div>

        <Button variant="ghost" size="icon" aria-label="Notifications" className="text-muted-foreground hover:bg-accent hover:text-foreground">
          <Bell className="h-4 w-4" />
        </Button>

        <Separator orientation="vertical" className="h-8 bg-border" />

        <div className="flex items-center gap-3">
          <div className="hidden text-right sm:block">
            <p className="text-sm font-medium text-foreground">
              {user?.user_metadata?.full_name ?? user?.email ?? "Operator"}
            </p>
            <p className="text-xs text-muted-foreground">{user?.email}</p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={handleSignOut}
            className="gap-2 border-border bg-transparent text-foreground hover:bg-accent hover:text-foreground"
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </div>
      </div>
    </header>
  );
}
