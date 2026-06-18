import { useLocation } from "react-router-dom";
import { Bell, LogOut, Search } from "lucide-react";
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
}

export function TopBar({ user }: TopBarProps) {
  const { pathname } = useLocation();
  const title = getPageTitle(pathname);

  async function handleSignOut() {
    await signOut();
  }

  return (
    <header className="flex h-16 items-center justify-between border-b border-white/5 bg-[#0D1117] px-6">
      <div>
        <h1 className="text-xl font-semibold text-white">{title}</h1>
        <p className="text-sm text-white/45">Manage your dive operation insights</p>
      </div>

      <div className="flex items-center gap-4">
        <div className="relative hidden md:block">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-white/35" />
          <Input
            placeholder="Search..."
            className="w-64 border-white/10 bg-[#161B22] pl-9 text-white placeholder:text-white/35"
            aria-label="Search"
          />
        </div>

        <Button variant="ghost" size="icon" aria-label="Notifications" className="text-white/70 hover:bg-white/5 hover:text-white">
          <Bell className="h-4 w-4" />
        </Button>

        <Separator orientation="vertical" className="h-8 bg-white/10" />

        <div className="flex items-center gap-3">
          <div className="hidden text-right sm:block">
            <p className="text-sm font-medium text-white">
              {user?.user_metadata?.full_name ?? user?.email ?? "Operator"}
            </p>
            <p className="text-xs text-white/45">{user?.email}</p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={handleSignOut}
            className="gap-2 border-white/10 bg-transparent text-white hover:bg-white/5"
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </div>
      </div>
    </header>
  );
}
